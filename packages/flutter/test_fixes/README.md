## Directory contents

The Dart files and golden master `.expect` files in this directory are used to
test the [`dart fix` framework](https://dart.dev/tools/dart-fix) refactorings used by the Flutter framework.

See the flutter/packages/flutter/lib/fix_data.yaml file for the current package:flutter
data driven fixes.

## When making structural changes to this directory

Note that the tests in this directory are also invoked from external repositories.
Specifically, the CI system for the dart-lang/sdk repo runs these tests in order to
ensure that changes to the dart fix file format do not break Flutter.

See [tools/bots/flutter/analyze_flutter_flutter.sh](https://github.com/dart-lang/sdk/blob/master/tools/bots/flutter/analyze_flutter_flutter.sh)
for where the tests are invoked.

When possible, please coordinate changes to this directory that might affect the
`analyze_flutter_flutter.sh` script.
