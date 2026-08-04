param(
	[string]$FilePath
)

function Get-SHA1Hash {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[Alias('FullName', 'Path')]
		[string]$FilePath
	)

	process {
		if (-not (Test-Path -LiteralPath $FilePath)) {
			throw "File not found: $FilePath"
		}

		Get-FileHash -LiteralPath $FilePath -Algorithm SHA1
	}
}

if ($FilePath) {
	Get-SHA1Hash -FilePath $FilePath
}
