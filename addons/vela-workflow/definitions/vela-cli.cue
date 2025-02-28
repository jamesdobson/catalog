import (
	"vela/op"
)

"vela-cli": {
	type: "workflow-step"
	annotations: {
		"definition.oam.dev/example-url": "https://raw.githubusercontent.com/kubevela/workflow/main/examples/workflow-run/apply-terraform-resource.yaml"
	}
	description: "Run a vela command"
}
template: {
	mountsArray: [
		if parameter.storage != _|_ && parameter.storage.secret != _|_ for v in parameter.storage.secret {
			{
				mountPath: v.mountPath
				if v.subPath != _|_ {
					subPath: v.subPath
				}
				name: v.name
			}
		},
	]

	volumesList: [
		if parameter.storage != _|_ && parameter.storage.secret != _|_ for v in parameter.storage.secret {
			{
				name: v.name
				secret: {
					defaultMode: v.defaultMode
					secretName:  v.secretName
					if v.items != _|_ {
						items: v.items
					}
				}
			}
		},
	]

	deDupVolumesArray: [
		for val in [
			for i, vi in volumesList {
				for j, vj in volumesList if j < i && vi.name == vj.name {
					_ignore: true
				}
				vi
			},
		] if val._ignore == _|_ {
			val
		},
	]

	job: op.#Apply & {
		value: {
			apiVersion: "batch/v1"
			kind:       "Job"
			metadata: {
				name: "\(context.name)-\(context.stepName)-\(context.stepSessionID)"
				if parameter.serviceAccountName == "kubevela-vela-core" {
					namespace: "vela-system"
				}
				if parameter.serviceAccountName != "kubevela-vela-core" {
					namespace: context.namespace
				}
			}
			spec: {
				backoffLimit: 3
				template: {
					labels: {
						"workflowrun.oam.dev/step-name": "\(context.name)-\(context.stepName)"
					}
					spec: {
						containers: [
							{
								name:         "\(context.name)-\(context.stepName)-\(context.stepSessionID)-job"
								image:        parameter.image
								command:      parameter.command
								volumeMounts: mountsArray
							},
						]
						restartPolicy:  "Never"
						serviceAccount: parameter.serviceAccountName
						volumes:        deDupVolumesArray
					}
				}
			}
		}
	}

	log: op.#Log & {
		source: {
			resources: [{labelSelector: {
				"workflowrun.oam.dev/step-name": "\(context.name)-\(context.stepName)"
			}}]
		}
	}

	fail: op.#Steps & {
		if job.value.status.failed != _|_ {
			if job.value.status.failed > 2 {
				breakWorkflow: op.#Fail & {
					message: "failed to execute vela command"
				}
			}
		}
	}

	wait: op.#ConditionalWait & {
		continue: job.value.status.succeeded != _|_ && job.value.status.succeeded > 0
	}

	parameter: {
		// +usage=Specify the name of the addon.
		addonName: string
		// +usage=Specify the vela command
		command: [...string]
		// +usage=Specify the image
		image: *"oamdev/vela-cli:v1.6.4" | string
		// +usage=specify serviceAccountName want to use
		serviceAccountName: *"kubevela-vela-core" | string
		storage?: {
			// +usage=Mount Secret type storage
			secret?: [...{
				name:        string
				mountPath:   string
				subPath?:    string
				defaultMode: *420 | int
				secretName:  string
				items?: [...{
					key:  string
					path: string
					mode: *511 | int
				}]
			}]
		}
	}
}
