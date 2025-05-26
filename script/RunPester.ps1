$pesterConfig = New-PesterConfiguration;
$pesterConfig.Output.Verbosity = 'Detailed';
$pesterConfig.Run.Exit = $true;
$pesterConfig.Run.Path = ".\test";

Invoke-Pester -Configuration $pesterConfig;
Exit $LASTEXITCODE;
