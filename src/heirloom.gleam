//// heirloom — split a secret into printable cards; any K of N bring it back.
////
//// Library entry points live in `heirloom/kit` (split and recover),
//// `heirloom/shamir`, `heirloom/qr` and `heirloom/card`. This module is the
//// command-line program.

import heirloom/cli

pub fn main() -> Nil {
  cli.run(cli.argv())
}
