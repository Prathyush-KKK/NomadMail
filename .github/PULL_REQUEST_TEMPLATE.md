## Summary

Describe the change and why it is needed.

## Validation

Paste the commands you ran and their result.

```powershell
node --check .\service\nomadmail-service.mjs
.\scripts\validate.ps1
```

## Safety Checklist

- [ ] No runtime mailbox data, exports, logs, local config, secrets, or token caches are committed.
- [ ] Mailbox reads still require approved source and scope.
- [ ] Send actions still require explicit approval of the exact draft.
- [ ] Trash/delete actions still require double confirmation.
- [ ] Archive imports remain read-only.
- [ ] Documentation was updated for user-facing behavior changes.
