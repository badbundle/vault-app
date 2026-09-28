# Security

## Reporting a problem

Please report security problems privately, through GitHub's private vulnerability reporting: open the **Security**
tab of this repository and choose **Report a vulnerability**.

Don't report them in a public issue, a pull request or the `VAULT` project on Trackslash. All three are public.

It helps to include:

- what you found, and what someone could do with it;
- the version and build of Vault, and of iOS, you saw it on;
- the steps to see it happen.

## What's in scope

- The Vault app for iPhone and iPad, and its AutoFill and widget extensions.
- The files it keeps on the device, and the backups and transfers it makes.
- The code in this repository.

These aren't in scope:

- iOS itself, and iPhones that are jailbroken or already compromised.
- Services you keep backups in, such as iCloud Drive.
- The limits listed under "Accepted limits" in [`docs/security-model.md`](./docs/security-model.md). If you think one
  of them shouldn't be accepted, a report is still welcome.

## What to expect

- We'll reply to say we've got your report, and keep you told as we look into it.
- We'll agree with you when the problem, and its fix, can be described in public. Until then, please keep it private.
- Once a fix is released, we'll thank you in its notes, if you'd like.

[`docs/security-model.md`](./docs/security-model.md) lists what Vault promises, and the limits it accepts.
