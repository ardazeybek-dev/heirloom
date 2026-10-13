# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Use
[GitHub's private vulnerability reporting](https://github.com/ardazeybek-dev/heirloom/security/advisories/new)
instead. You will get an answer within a week.

Especially welcome: anything that lets fewer than K cards learn something about the secret, weak or
predictable randomness, ways a card could recover to a *different* secret without being flagged, and
ways the playground could leak data despite its Content-Security-Policy.

## Scope and assumptions

heirloom assumes the device used to split or recover is not compromised. It does not defend against
malware, screen recording, or K holders who choose to collude. See the security model in the README.
