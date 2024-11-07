# Troubleshooting Steps

## Resolving Download to TAR Failures

If you encounter failures during the download to TAR process, especially for images like `multicluster-global-hub-operator-product`, it may indicate a missing entry in the operator map file. You might see an error message similar to this:

```plaintext
fatal: [localhost]: FAILED! => {"msg": "The task includes an option with an undefined variable. The error was: 'dict object' has no attribute 'multicluster-global-hub-operator-product'. 'dict object' has no attribute 'multicluster-global-hub-operator-product'\n\nThe error appears to be in '/home/lab-user/workspace/ocp4-disconnected-helper/playbooks/tasks/get-operator-catalog-channels.yml': line 25, column 3, but may\nbe elsewhere in the file depending on the exact syntax problem.\n\nThe offending line appears to be:\n\n\n- name: Loop through the operator packages that don't have a channel defined\n  ^ here\n"}
```

To troubleshoot this issue, follow these steps:

1. **Verify Operator Entry in the Map File**  
   Ensure the operator exists in the operator map file by running:
   ```bash
   cat /tmp/operator_map.txt | grep multicluster-global-hub-operator-product
   ```

2. **Check `.oc-mirror.log` Status**  
   To get more details on the download process, review the `.oc-mirror.log` file by running:
   ```bash
   cd /opt/images
   tail -f .oc-mirror.log
   ```

These steps will help you identify missing entries in the operator map file and monitor the download progress through `.oc-mirror.log` for further troubleshooting.