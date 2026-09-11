@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # cmdpeek is an interactive terminal tool. The TUI and the human output paths
        # draw to the console on purpose and must not be capturable as pipeline output.
        'PSAvoidUsingWriteHost'

        # Most catches here wrap a best-effort probe: reading a PE header, parsing a
        # cache, launching a binary with --help. A failure means "no answer for this
        # one", and the scan has to keep going. Swallowing is the intended behaviour.
        'PSAvoidUsingEmptyCatchBlock'

        # The plural is the noun: Get-CmdPeekCurrentOs, Get-CmdPeekInstallCommands,
        # Get-CmdPeekCatalogKits. Renaming them to satisfy the rule would make them
        # read worse and would break every caller.
        'PSUseSingularNouns'

        # Set-CmdPeekFavorite and friends take a state object and return a new one.
        # They touch nothing outside the caller's variable, so -WhatIf would be a lie.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
