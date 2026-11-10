#!/usr/bin/env bash
# =============================================================================
#  DO256 · Chapters 1-5 Review  ·  "Pizza Planet goes virtual"  🍕
#
#  One script for the whole review:
#     bash review.sh setup        # create the scenario (and break a few things)
#     bash review.sh check        # grade all 8 tasks
#     bash review.sh check 4      # grade one task
#     bash review.sh watch        # live scoreboard, ticks tasks off as they are done
#     bash review.sh hint 4       # show a hint for task 4
#     bash review.sh solve 4      # apply the solution for task 4 (instructor)
#     bash review.sh solve all    # apply every solution
#     bash review.sh cleanup      # remove everything the review created
#     bash review.sh reset        # cleanup + setup (start over)
#
#  Run it on the workstation, logged in as a cluster admin:
#     oc login -u admin -p redhatocp https://api.ocp4.example.com:6443
# =============================================================================
set -uo pipefail

KITCHEN=pizza-kitchen        # main project: the VM, policies, NAD, answers
FRONT=pizza-front            # where the "customers" live
DELIVERY=pizza-delivery      # needs a primary user-defined network
OSIMG=openshift-virtualization-os-images
ADP=openshift-adp
STUDENT=developer            # the user who gets the VM role in task 1

# ---------- colours -----------------------------------------------------------
if [ -t 1 ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; M=$'\e[35m'; C=$'\e[36m'; W=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else R=; G=; Y=; B=; M=; C=; W=; D=; N=; fi
say()   { printf '%s\n' "$*"; }
title() { printf '\n%s%s%s\n' "$W$M" "$*" "$N"; }
ok()    { printf '   %s✔%s %s\n' "$G" "$N" "$*"; }
bad()   { printf '   %s✘%s %s\n' "$R" "$N" "$*"; }
info()  { printf '   %s•%s %s\n' "$C" "$N" "$*"; }
warn()  { printf '   %s!%s %s\n' "$Y" "$N" "$*"; }

need_admin() {
  if ! oc whoami >/dev/null 2>&1; then
    say "${R}Not logged in.${N} Run:  oc login -u admin -p redhatocp https://api.ocp4.example.com:6443"; exit 1
  fi
  if [ "$(oc auth can-i '*' '*' --all-namespaces 2>/dev/null)" != "yes" ]; then
    say "${R}You need cluster-admin for this script.${N} Log in as admin."; exit 1
  fi
}

# json helper: jget '<python expression on d>'  (reads JSON from stdin)
jget() { python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
try: v=($1)
except Exception: v=''
print('' if v is None else v)"; }

# pick a ready boot source (DataSource) for the VM
pick_datasource() {
  oc get datasource -n "$OSIMG" -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
ready=[i['metadata']['name'] for i in d.get('items',[])
       if any(c.get('type')=='Ready' and c.get('status')=='True' for c in i.get('status',{}).get('conditions',[]))]
pref=['rhel9','rhel10','centos-stream9','centos-stream10','fedora','rhel8']
for p in pref:
    if p in ready: print(p); break
else:
    print(ready[0] if ready else '')"
}

answer() { oc get configmap pizza-answers -n "$KITCHEN" -o "jsonpath={.data.$1}" 2>/dev/null | tr 'A-Z' 'a-z' | tr -d ' \n'; }

# ==============================================================================
# SETUP
# ==============================================================================
do_setup() {
  need_admin
  title "🍕  Setting up Pizza Planet ..."

  for ns in "$KITCHEN" "$FRONT"; do
    oc get ns "$ns" >/dev/null 2>&1 || oc create namespace "$ns" >/dev/null
    info "project $ns ready"
  done
  oc label ns "$FRONT" pizza-role=customers --overwrite >/dev/null

  # The boot-source "menu": tell students which DataSource to use
  ds=$(pick_datasource)
  if [ -z "$ds" ]; then
    warn "No ready DataSource found in $OSIMG — task 3 needs one (check Virtualization › Bootable volumes)."
    ds=rhel9
  fi
  oc create configmap pizza-menu -n "$KITCHEN" --from-literal=datasource="$ds" \
     --from-literal=datasource-namespace="$OSIMG" --dry-run=client -o yaml | oc apply -f - >/dev/null
  info "boot source on the menu: ${W}$ds${N} (configmap pizza-menu)"

  # Task 4 problem: a deny-all policy, nothing allowed in
  oc apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: $KITCHEN
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF
  info "the kitchen door is locked (NetworkPolicy deny-all)"

  # Task 5 problem: namespace created WITHOUT the primary-UDN label + a UDN that cannot work
  if ! oc get ns "$DELIVERY" >/dev/null 2>&1; then
    oc create namespace "$DELIVERY" >/dev/null
  fi
  oc apply -f - >/dev/null 2>&1 <<EOF
apiVersion: k8s.ovn.org/v1
kind: UserDefinedNetwork
metadata:
  name: delivery-lane
  namespace: $DELIVERY
spec:
  topology: Layer2
  layer2:
    role: Primary
    subnets: ["10.200.0.0/16"]
    ipam:
      lifecycle: Persistent
EOF
  info "delivery lane created ... or was it? (project $DELIVERY)"

  # Task 6 problem: NAD with a typo in the bridge name
  oc apply -f - >/dev/null <<EOF
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: pizza-bridge
  namespace: $KITCHEN
  annotations:
    k8s.v1.cni.cncf.io/resourceName: bridge.network.kubevirt.io/br-piza
spec:
  config: '{"cniVersion":"0.3.1","name":"pizza-bridge","type":"bridge","bridge":"br-piza","macspoofchk":true}'
EOF
  info "the oven wiring was installed by an intern (NAD pizza-bridge)"

  # Task 7: answers sheet
  oc get configmap pizza-answers -n "$KITCHEN" >/dev/null 2>&1 || \
    oc create configmap pizza-answers -n "$KITCHEN" >/dev/null
  info "answer sheet ready (configmap pizza-answers)"

  # Task 8 pre-check
  if oc get dataprotectionapplication -n "$ADP" >/dev/null 2>&1 && \
     [ -n "$(oc get dataprotectionapplication -n "$ADP" -o name 2>/dev/null)" ]; then
    info "OADP is installed — task 8 is on"
  else
    warn "No DataProtectionApplication in $ADP — task 8 needs OADP set up (Chapter 4.3)."
  fi

  say ""
  say "${G}${W}Pizza Planet is open for business (sort of).${N}  Now run:  ${W}bash review.sh check${N}"
}

# ==============================================================================
# CHECKS — each prints its own lines and returns 0 (pass) or 1 (fail)
# ==============================================================================
check1() {
  title "Task 1 · Ch1 · Who's on the staff?"
  local p=0
  if [ "$(oc auth can-i create virtualmachines.kubevirt.io -n "$KITCHEN" --as "$STUDENT" 2>/dev/null)" = "yes" ]; then
    ok "$STUDENT can create VMs in $KITCHEN"
  else bad "$STUDENT cannot create VMs in $KITCHEN yet"; p=1; fi
  if [ "$(oc auth can-i delete namespace "$KITCHEN" --as "$STUDENT" 2>/dev/null)" = "no" ]; then
    ok "...but cannot delete the project (least privilege)"
  else bad "$STUDENT has too much power — use kubevirt.io:edit, not admin"; p=1; fi
  return $p
}

check2() {
  title "Task 2 · Ch5 · Pick the oven size"
  local j; j=$(oc get virtualmachineinstancetype pizza-small -n "$KITCHEN" -o json 2>/dev/null)
  if [ -z "$j" ]; then bad "VirtualMachineInstancetype pizza-small not found in $KITCHEN"; return 1; fi
  local cpu mem; cpu=$(echo "$j" | jget "d['spec']['cpu']['guest']"); mem=$(echo "$j" | jget "d['spec']['memory']['guest']")
  local p=0
  [ "$cpu" = "1" ] && ok "1 vCPU" || { bad "guest CPU is '$cpu', expected 1"; p=1; }
  [ "$mem" = "2Gi" ] && ok "2Gi memory" || { bad "guest memory is '$mem', expected 2Gi"; p=1; }
  return $p
}

check3() {
  title "Task 3 · Ch5 · Fire up the oven"
  local j; j=$(oc get vm oven1 -n "$KITCHEN" -o json 2>/dev/null)
  if [ -z "$j" ]; then bad "VM oven1 not found in $KITCHEN"; return 1; fi
  local p=0
  [ "$(echo "$j" | jget "d['spec']['instancetype']['name']")" = "pizza-small" ] && ok "uses instance type pizza-small" || { bad "VM does not use instance type pizza-small"; p=1; }
  local vl tl; vl=$(echo "$j" | jget "d['metadata']['labels']['app']"); tl=$(echo "$j" | jget "d['spec']['template']['metadata']['labels']['app']")
  if [ "$vl" = "oven" ] || [ "$tl" = "oven" ]; then ok "VM has label app=oven"
  else bad "VM needs label app=oven (tasks 4 and 8 depend on it)"; p=1; fi
  if [ "$vl" = "oven" ] && [ "$tl" != "oven" ]; then warn "tip: also add app=oven under spec.template.metadata.labels so the VM pod gets it"; fi
  if [ "$tl" = "oven" ] && [ "$vl" != "oven" ]; then warn "tip: also add app=oven under metadata.labels so the backup in task 8 finds the VM"; fi
  local phase; phase=$(oc get vmi oven1 -n "$KITCHEN" -o jsonpath='{.status.phase}' 2>/dev/null)
  if [ "$phase" = "Running" ]; then ok "oven1 is Running 🔥"
  else bad "oven1 is not Running yet (phase: ${phase:-none}) — check: oc get dv,vmi -n $KITCHEN"; p=1; fi
  return $p
}

check4() {
  title "Task 4 · Ch2 · Customers can't reach the oven"
  local res
  res=$(oc get networkpolicy -n "$KITCHEN" -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); good=False
for p in d.get('items',[]):
    s=p['spec']
    if s.get('podSelector',{}).get('matchLabels',{}).get('app')!='oven': continue
    for r in s.get('ingress',[]) or []:
        ports=[str(x.get('port')) for x in r.get('ports',[]) or []]
        frm=r.get('from',[]) or []
        nsok=any((f.get('namespaceSelector',{}).get('matchLabels',{}).get('pizza-role')=='customers' or
                  f.get('namespaceSelector',{}).get('matchLabels',{}).get('kubernetes.io/metadata.name')=='$FRONT')
                 and not f.get('podSelector',{}).get('matchLabels') and not f.get('podSelector',{}).get('matchExpressions') for f in frm)
        if '8080' in ports and nsok: good=True
print('yes' if good else 'no')")
  local p=0
  if oc get networkpolicy deny-all -n "$KITCHEN" >/dev/null 2>&1; then ok "deny-all is still in place (good — don't delete it!)"
  else bad "deny-all was deleted — keep it and ADD an allow policy instead"; p=1; fi
  [ "$res" = "yes" ] && ok "a policy lets $FRONT reach app=oven on TCP 8080" || { bad "no policy allows namespace $FRONT → app=oven on port 8080"; p=1; }
  return $p
}

check5() {
  title "Task 5 · Ch2 · The delivery lane won't open"
  local p=0
  local lbl; lbl=$(oc get ns "$DELIVERY" -o json 2>/dev/null | jget "'yes' if 'k8s.ovn.org/primary-user-defined-network' in d['metadata'].get('labels',{}) else 'no'")
  [ "$lbl" = "yes" ] && ok "$DELIVERY has the primary-UDN label" || { bad "$DELIVERY is missing label k8s.ovn.org/primary-user-defined-network"; p=1; }
  local st; st=$(oc get userdefinednetwork delivery-lane -n "$DELIVERY" -o json 2>/dev/null | jget "'True' if any(c.get('type') in ('NetworkCreated','NetworkReady') and c.get('status')=='True' for c in d['status']['conditions']) else 'False'")
  [ "$st" = "True" ] && ok "UDN delivery-lane is created (10.200.0.0/16)" || { bad "UDN delivery-lane is not ready — oc describe userdefinednetwork delivery-lane -n $DELIVERY"; p=1; }
  return $p
}

check6() {
  title "Task 6 · Ch2 · Crossed wires"
  local cfg; cfg=$(oc get net-attach-def pizza-bridge -n "$KITCHEN" -o jsonpath='{.spec.config}' 2>/dev/null)
  if [ -z "$cfg" ]; then bad "NAD pizza-bridge not found in $KITCHEN"; return 1; fi
  local br; br=$(echo "$cfg" | jget "d.get('bridge')")
  local p=0
  [ "$br" = "br-pizza" ] && ok "bridge is br-pizza" || { bad "bridge is '$br' — the node bridge is called br-pizza"; p=1; }
  [ "$(echo "$cfg" | jget "d.get('type')")" = "bridge" ] && ok "CNI type is bridge" || { bad "CNI type must be bridge"; p=1; }
  local ann; ann=$(oc get net-attach-def pizza-bridge -n "$KITCHEN" -o json | jget "d['metadata'].get('annotations',{}).get('k8s.v1.cni.cncf.io/resourceName','')")
  [ "$ann" = "bridge.network.kubevirt.io/br-pizza" ] && ok "resourceName annotation matches" || { bad "annotation k8s.v1.cni.cncf.io/resourceName should end in /br-pizza"; p=1; }
  return $p
}

check7() {
  title "Task 7 · Ch2.7 + Ch3 · Detective round"
  local p=0
  local prov; prov=$(oc get provider -n openshift-mtv -o json 2>/dev/null | jget "[i['metadata']['name'] for i in d['items'] if i['spec'].get('type')=='openshift'][0]" | tr 'A-Z' 'a-z')
  if [ -z "$prov" ]; then warn "MTV not found — skipping the provider question"
  elif [ "$(answer mtv-provider)" = "$prov" ]; then ok "mtv-provider is right"
  else bad "answer 'mtv-provider' is missing or wrong"; p=1; fi
  [ "$(answer migration)" = "warm" ] && ok "migration = warm" || { bad "answer 'migration' is missing or wrong (cold or warm?)"; p=1; }
  [ "$(answer iscsi-port)" = "3260" ] && ok "iscsi-port = 3260" || { bad "answer 'iscsi-port' is missing or wrong"; p=1; }
  return $p
}

check8() {
  title "Task 8 · Ch4 · Burnt pizza: back up, then restore"
  local p=0
  local bp; bp=$(oc get backup.velero.io oven-backup -n "$ADP" -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$bp" = "Completed" ] && ok "Backup oven-backup Completed" || { bad "Backup oven-backup phase: ${bp:-not found}"; p=1; }
  local sel; sel=$(oc get backup.velero.io oven-backup -n "$ADP" -o jsonpath='{.spec.labelSelector.matchLabels.app}' 2>/dev/null)
  [ "$sel" = "oven" ] && ok "backup selects app=oven" || { bad "backup should use labelSelector app=oven"; p=1; }
  local rp; rp=$(oc get restore.velero.io oven-restore -n "$ADP" -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$rp" = "Completed" ] && ok "Restore oven-restore Completed" || { bad "Restore oven-restore phase: ${rp:-not found}"; p=1; }
  oc get vm oven1 -n "$KITCHEN" >/dev/null 2>&1 && ok "oven1 is back" || { bad "VM oven1 is missing"; p=1; }
  return $p
}

do_check() {
  need_admin
  local list=("$@"); [ ${#list[@]} -eq 0 ] && list=(1 2 3 4 5 6 7 8)
  local pass=0
  for t in "${list[@]}"; do "check$t" && pass=$((pass+1)); done
  say ""
  local slices="" i
  for i in $(seq 1 ${#list[@]}); do if [ "$i" -le "$pass" ]; then slices+="🍕"; else slices+="⬜"; fi; done
  say "${W}Score: $pass / ${#list[@]}${N}   $slices"
  if [ "$pass" -eq "${#list[@]}" ] && [ ${#list[@]} -eq 8 ]; then
    say "${G}${W}🎉  Pizza Planet is fully virtual! Post 'PIZZA DELIVERED 8/8' in the chat.${N}"
  fi
}

# ==============================================================================
# HINTS
# ==============================================================================
do_hint() {
  case "${1:-}" in
    1) say "${Y}Hint 1:${N} Console: User Management › RoleBindings › Create binding
        Namespace role binding · namespace $KITCHEN · role kubevirt.io:edit · subject User $STUDENT
        CLI: oc adm policy add-role-to-user kubevirt.io:edit $STUDENT -n $KITCHEN";;
    2) say "${Y}Hint 2:${N} Console: Virtualization › InstanceTypes › User InstanceTypes › Create (project $KITCHEN)
        kind VirtualMachineInstancetype · spec.cpu.guest: 1 · spec.memory.guest: 2Gi
        CLI: oc apply -f <yaml> ; oc get virtualmachineinstancetype -n $KITCHEN";;
    3) say "${Y}Hint 3:${N} Menu: Workloads › ConfigMaps › pizza-menu  → which boot volume to use
        Console: Virtualization › Catalog › InstanceTypes › boot volume › User provided › pizza-small › name oven1
        Customize VirtualMachine › YAML: add app: oven under metadata.labels AND spec.template.metadata.labels
        CLI: VM with spec.instancetype {kind: VirtualMachineInstancetype, name: pizza-small} + DataSource dataVolumeTemplate";;
    4) say "${Y}Hint 4:${N} Don't delete deny-all — policies ADD up.
        Console: Networking › NetworkPolicies › Create NetworkPolicy · pod selector app=oven
        · ingress › allow pods from inside the cluster › namespace selector pizza-role=customers · port TCP 8080";;
    5) say "${Y}Hint 5:${N} Console: Networking › UserDefinedNetworks › delivery-lane › Conditions
        The label k8s.ovn.org/primary-user-defined-network must be on the project WHEN IT IS CREATED.
        Delete project $DELIVERY › re-create it with the label (+ Import YAML) › re-create the UDN.";;
    6) say "${Y}Hint 6:${N} Console: Networking › NetworkAttachmentDefinitions › pizza-bridge › YAML
        Spelling! br-piza → br-pizza, in spec.config AND the resourceName annotation.
        CLI: oc edit net-attach-def pizza-bridge -n $KITCHEN";;
    7) say "${Y}Hint 7:${N} Console: Migration › Providers for virtualization (type OpenShift Virtualization)
        Workloads › ConfigMaps › pizza-answers › Actions › Edit ConfigMap › Add key/value
        Which migration copies data while the VM keeps running? Which TCP port does iSCSI use?
        CLI: oc set data cm/pizza-answers -n $KITCHEN mtv-provider=... migration=... iscsi-port=...";;
    8) say "${Y}Hint 8:${N} Console: Operators › Installed Operators › OADP (project $ADP) › Backup tab › Create Backup
        includedNamespaces [$KITCHEN] · labelSelector app=oven · snapshotMoveData: true
        Wait for Completed › delete oven1 › Restore tab › Create Restore with backupName: oven-backup";;
    *) say "Usage: bash review.sh hint <1-8>";;
  esac
}

# ==============================================================================
# SOLUTIONS
# ==============================================================================
solve1() {
  oc adm policy add-role-to-user kubevirt.io:edit "$STUDENT" -n "$KITCHEN" >/dev/null
  info "$STUDENT got kubevirt.io:edit in $KITCHEN"
}
solve2() {
  oc apply -f - <<EOF
apiVersion: instancetype.kubevirt.io/v1beta1
kind: VirtualMachineInstancetype
metadata:
  name: pizza-small
  namespace: $KITCHEN
spec:
  cpu:
    guest: 1
  memory:
    guest: 2Gi
EOF
}
solve3() {
  local ds; ds=$(oc get cm pizza-menu -n "$KITCHEN" -o jsonpath='{.data.datasource}' 2>/dev/null); ds=${ds:-$(pick_datasource)}
  oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: oven1
  namespace: $KITCHEN
  labels:
    app: oven
spec:
  runStrategy: Always
  instancetype:
    kind: VirtualMachineInstancetype
    name: pizza-small
  preference:
    inferFromVolume: rootdisk
  dataVolumeTemplates:
  - metadata:
      name: oven1-rootdisk
      labels:
        app: oven
    spec:
      sourceRef:
        kind: DataSource
        name: $ds
        namespace: $OSIMG
      storage:
        resources:
          requests:
            storage: 30Gi
  template:
    metadata:
      labels:
        app: oven
    spec:
      domain:
        devices: {}
      volumes:
      - name: rootdisk
        dataVolume:
          name: oven1-rootdisk
EOF
  info "oven1 is booting from $ds — give it a few minutes (oc get vmi -n $KITCHEN -w)"
}
solve4() {
  oc apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-customers
  namespace: $KITCHEN
spec:
  podSelector:
    matchLabels:
      app: oven
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          pizza-role: customers
    ports:
    - protocol: TCP
      port: 8080
EOF
}
solve5() {
  oc delete ns "$DELIVERY" --wait=true >/dev/null 2>&1
  oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $DELIVERY
  labels:
    k8s.ovn.org/primary-user-defined-network: ""
EOF
  oc apply -f - <<EOF
apiVersion: k8s.ovn.org/v1
kind: UserDefinedNetwork
metadata:
  name: delivery-lane
  namespace: $DELIVERY
spec:
  topology: Layer2
  layer2:
    role: Primary
    subnets: ["10.200.0.0/16"]
    ipam:
      lifecycle: Persistent
EOF
}
solve6() {
  oc apply -f - <<EOF
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: pizza-bridge
  namespace: $KITCHEN
  annotations:
    k8s.v1.cni.cncf.io/resourceName: bridge.network.kubevirt.io/br-pizza
spec:
  config: '{"cniVersion":"0.3.1","name":"pizza-bridge","type":"bridge","bridge":"br-pizza","macspoofchk":true}'
EOF
}
solve7() {
  local prov; prov=$(oc get provider -n openshift-mtv -o json 2>/dev/null | jget "[i['metadata']['name'] for i in d['items'] if i['spec'].get('type')=='openshift'][0]")
  oc get cm pizza-answers -n "$KITCHEN" >/dev/null 2>&1 || oc create cm pizza-answers -n "$KITCHEN" >/dev/null
  oc set data cm/pizza-answers -n "$KITCHEN" mtv-provider="${prov:-host}" migration=warm iscsi-port=3260 >/dev/null
  info "mtv-provider=${prov:-host} · migration=warm · iscsi-port=3260"
}
solve8() {
  oc apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: oven-backup
  namespace: $ADP
spec:
  includedNamespaces: [$KITCHEN]
  labelSelector:
    matchLabels:
      app: oven
  snapshotMoveData: true
  ttl: 24h0m0s
EOF
  info "waiting for the backup to complete ..."
  for _ in $(seq 1 90); do
    ph=$(oc get backup.velero.io oven-backup -n "$ADP" -o jsonpath='{.status.phase}' 2>/dev/null)
    case "$ph" in Completed) break;; Failed|PartiallyFailed|FailedValidation) warn "backup $ph"; return 1;; esac
    sleep 10
  done
  info "backup $ph — burning the pizza (deleting oven1) ..."
  oc delete vm oven1 -n "$KITCHEN" --wait=true >/dev/null 2>&1
  oc apply -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: oven-restore
  namespace: $ADP
spec:
  backupName: oven-backup
  restorePVs: true
EOF
  info "restore started — watch: oc get restore.velero.io oven-restore -n $ADP -w"
}

do_solve() {
  need_admin
  case "${1:-}" in
    all) for t in 1 2 3 4 5 6 7 8; do title "Solving task $t"; "solve$t"; done;;
    [1-8]) title "Solving task $1"; "solve$1";;
    *) say "Usage: bash review.sh solve <1-8|all>";;
  esac
}

# ==============================================================================
# CLEANUP
# ==============================================================================
do_cleanup() {
  need_admin
  title "🧹  Closing Pizza Planet ..."
  oc delete restore.velero.io oven-restore -n "$ADP" --ignore-not-found >/dev/null 2>&1 && info "restore oven-restore removed"
  if command -v velero >/dev/null 2>&1; then velero backup delete oven-backup -n "$ADP" --confirm >/dev/null 2>&1
  else oc delete backup.velero.io oven-backup -n "$ADP" --ignore-not-found >/dev/null 2>&1; fi
  info "backup oven-backup removed"
  # stop and delete VMs first so the projects are not held up by running VMs
  oc delete vm --all -n "$KITCHEN" --ignore-not-found --wait=false >/dev/null 2>&1
  for ns in "$KITCHEN" "$FRONT" "$DELIVERY"; do
    oc delete ns "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 && info "deleting project $ns"
  done
  printf '   %s•%s waiting for the projects to disappear ' "$C" "$N"
  local i left
  for i in $(seq 1 60); do
    left=0
    for ns in "$KITCHEN" "$FRONT" "$DELIVERY"; do oc get ns "$ns" >/dev/null 2>&1 && left=$((left+1)); done
    [ "$left" -eq 0 ] && break
    printf '.'; sleep 5
  done
  say ""
  if [ "$left" -eq 0 ]; then say "${G}${W}Clean. Run  bash review.sh setup  to start again.${N}"
  else warn "$left project(s) still terminating — check: oc get ns | grep pizza"; fi
}

# ==============================================================================
# WATCH — live scoreboard that ticks tasks off as students finish them
# ==============================================================================
do_watch() {
  need_admin
  local every=${1:-10}
  trap 'tput cnorm 2>/dev/null; say ""; exit 0' INT TERM
  tput civis 2>/dev/null
  local t out pass board slices
  declare -A done_at=()
  while true; do
    pass=0; board=""
    for t in 1 2 3 4 5 6 7 8; do
      if out=$("check$t" 2>/dev/null); then
        pass=$((pass+1))
        [ -z "${done_at[$t]:-}" ] && done_at[$t]=$(date +%H:%M)
        board+="$(printf '%s' "$out" | sed -n '/Task /{p;q}')  ${G}✔ DONE${N} ${D}at ${done_at[$t]}${N}"$'\n'
      else
        unset "done_at[$t]"
        board+="$(printf '%s' "$out" | sed '/^$/d' | sed "1s/\$/  ${Y}⏳ pending${N}/")"$'\n'
      fi
    done
    slices=""; for t in $(seq 1 8); do if [ "$t" -le "$pass" ]; then slices+="🍕"; else slices+="⬜"; fi; done
    clear
    say "${W}${M}🍕  PIZZA PLANET · LIVE SCOREBOARD${N}   ${D}$(date +%H:%M:%S) · refreshes every ${every}s · Ctrl+C to stop${N}"
    printf '%s' "$board"
    say ""
    say "${W}Score: $pass / 8${N}   $slices"
    if [ "$pass" -eq 8 ]; then
      say "${G}${W}🎉  Pizza Planet is fully virtual! Post 'PIZZA DELIVERED 8/8' in the chat.${N}"
      tput cnorm 2>/dev/null; return 0
    fi
    sleep "$every"
  done
}

# ==============================================================================
banner() {
  say "${W}${R}  ___ _                 ___ _                 _   ${N}"
  say "${W}${Y} | _ (_)________ _     | _ \ |__ _ _ _  ___| |_ ${N}"
  say "${W}${G} |  _/ |_ /_ / _\` |    |  _/ / _\` | ' \/ -_)  _|${N}"
  say "${W}${B} |_| |_/__/__\__,_|    |_| |_\__,_|_||_\___|\__|${N}"
  say "${D}  DO256 · Chapters 1–5 review · 8 tasks · 🍕${N}"
}

cmd=${1:-}; shift || true
case "$cmd" in
  setup)   banner; do_setup;;
  check)   do_check "$@";;
  hint)    do_hint "$@";;
  solve)   do_solve "$@";;
  watch)   do_watch "$@";;
  cleanup) do_cleanup;;
  reset)   do_cleanup; do_setup;;
  *) banner; say "
Usage:
  bash review.sh setup          create the scenario
  bash review.sh check [N]      grade all tasks, or task N
  bash review.sh watch [secs]   live scoreboard: ticks tasks off as you finish them
  bash review.sh hint N         show a hint
  bash review.sh solve N|all    apply a solution (instructor)
  bash review.sh cleanup        remove everything
  bash review.sh reset          cleanup, then setup again";;
esac
