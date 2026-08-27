param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ProbName
)

# N95DIR must be no longer than 33 characters 33 + "/rf/" + 7 = 44. 7 is the longest rf filename (NASINFO).
# If it's longer, Nastran95 will truncate it and then be unable to open the rf files.
$env:N95DIR  = "C:/Users/victo/Documents/apps/N95"
$env:RFDIR   = "$env:N95DIR/rf"
# Warning, it dumps working files and output in the current directory. To be more standard, it should get
# the location of the input file and use that instaed, so you can call it from somewhere else.
$env:DIRCTY  = (Get-Location).Path
$env:DBMEM   = "12000000"
$env:OCMEM   = "2000000"
$env:NPTPNM  = "$env:DIRCTY\$ProbName.nptp"
$env:PLTNM   = "$env:DIRCTY\$ProbName.plt"
$env:DICTNM  = "$env:DIRCTY\$ProbName.dict"
$env:PUNCHNM = "$env:DIRCTY\$ProbName.pch"
$env:OPTPNM  = "$env:DIRCTY\$ProbName.opt"
$env:LOGNM   = "$env:DIRCTY\$ProbName.f04"
$env:F06     = "$env:DIRCTY\$ProbName.f06"
$env:IN12    = "$env:DIRCTY\$ProbName.in12"
$env:OUT11   = "$env:DIRCTY\$ProbName.out11"
$env:FTN11   = "$env:DIRCTY\$ProbName.f11"
$env:FTN12   = "$env:DIRCTY\$ProbName.f12"
$env:FTN13   = "$env:DIRCTY\$ProbName.f13"
$env:FTN14   = "$env:DIRCTY\$ProbName.f14"
$env:FTN15   = "$env:DIRCTY\$ProbName.f15"
$env:FTN16   = "$env:DIRCTY\$ProbName.f16"
$env:FTN17   = "$env:DIRCTY\$ProbName.f17"
$env:FTN18   = "$env:DIRCTY\$ProbName.f18"
$env:FTN19   = "$env:DIRCTY\$ProbName.f19"
$env:FTN20   = "$env:DIRCTY\$ProbName.f20"
$env:FTN21   = "$env:DIRCTY\$ProbName.f21"
$env:FTN22   = "$env:DIRCTY\$ProbName.f22"
$env:FTN23   = "$env:DIRCTY\$ProbName.f23"
$env:SOF1    = "$env:DIRCTY\$ProbName.sof1"
$env:SOF2    = "$env:DIRCTY\$ProbName.sof2"

Get-Content $ProbName | & "$env:N95DIR\bin\nastran.exe" | Out-File "$ProbName.f06"
