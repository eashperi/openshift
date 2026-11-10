# 🍕 Pizza Planet goes virtual — DO256 review, chapters 1–5

Eight small, hands-on tasks that touch every section covered so far. Some are builds, some are **troubleshooting** — the setup script quietly breaks a few things for you to fix.

## Run it (on the workstation, as admin)

```bash
oc login -u admin -p redhatocp https://api.ocp4.example.com:6443
curl -sLO https://raw.githubusercontent.com/eashperi/openshift/master/do256-review/review.sh
bash review.sh setup
bash review.sh check        # grade yourself any time
bash review.sh hint 3       # stuck? get a hint
```

## The tasks

| # | Chapter | Task | What to do |
|---|---|---|---|
| 1 | Ch1 · Auth & RBAC | **Who's on the staff?** | Save the cluster's identity provider name as key `idp` in configmap `pizza-answers` (project `pizza-kitchen`). Let user `developer` manage VMs in `pizza-kitchen` — but not delete the project. |
| 2 | Ch5 · Instance types | **Pick the oven size** | Create a `VirtualMachineInstancetype` named `pizza-small` in `pizza-kitchen`: 1 vCPU, 2Gi memory. |
| 3 | Ch5 · Boot sources | **Fire up the oven** | Create VM `oven1` in `pizza-kitchen` from the DataSource named in configmap `pizza-menu`, using instance type `pizza-small`, with template label `app=oven`. Get it Running. |
| 4 | Ch2 · Network policy | **Customers can't reach the oven** 🔧 | Someone locked the kitchen with `deny-all`. Keep it, and let project `pizza-front` (label `pizza-role=customers`) reach `app=oven` on TCP 8080. |
| 5 | Ch2 · UDN | **The delivery lane won't open** 🔧 | UDN `delivery-lane` (Layer2, primary, 10.200.0.0/16) in `pizza-delivery` is broken. Find out why and fix it. |
| 6 | Ch2 · Multihomed VMs | **Crossed wires** 🔧 | NAD `pizza-bridge` should connect to node bridge `br-pizza`. The intern made a typo. Fix it. |
| 7 | Ch2.7 + Ch3 · Storage & MTV | **Detective round** | Add to `pizza-answers`: `mtv-provider` (MTV provider of type openshift), `migration` (cold or warm: which keeps the VM running while data copies?), `iscsi-port` (iSCSI TCP port). |
| 8 | Ch4 · OADP | **Burnt pizza** | Back up `oven1` with Backup `oven-backup` (label `app=oven`), delete the VM, restore it with Restore `oven-restore`. |

🔧 = troubleshooting

## Instructor

```bash
bash review.sh solve 4      # solution for one task
bash review.sh solve all    # everything
bash review.sh cleanup      # remove all review projects, backup and restore
```
