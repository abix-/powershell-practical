function Add-Certificate {
    [CmdletBinding()]
    param
    (
        [Parameter(Position=1, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Position=2, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password
    )

    Write-Verbose -Message ('Installing certificate from path: {0}' -f $Path);

    try 
    {
        # Create the certificate
        $pfxcert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ErrorAction Stop;
        $KeyStorageFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bxor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bxor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet;
        Write-Verbose ('Key storage flags is: {0}' -f $KeyStorageFlags);
        $pfxcert.Import($Path, $Password, $KeyStorageFlags);

        # Create the X509 store and import the certificate
        $store = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store -ArgumentList My, LocalMachine -ErrorAction Stop;
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite);
        $store.Add($pfxcert);
        $store.Close();

        Write-Output -InputObject $pfxcert;
    }
    catch 
    {
        throw $_;
    }
}

function Set-CertificatePermission
{
    param
    (
        [Parameter(Position=1, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$pfxThumbPrint,

        [Parameter(Position=2, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$serviceAccount
    )

    $cert = Get-ChildItem -Path cert:\LocalMachine\My | ?{$_.ThumbPrint -eq $pfxThumbPrint; };

    # Specify the user, the permissions and the permission type
    $permission = "$($serviceAccount)","Read,FullControl","Allow"
    $accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission;

    # Location of the machine related keys
    $keyPath = $env:ProgramData + "\Microsoft\Crypto\RSA\MachineKeys\";
    $keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName;
    $keyFullPath = $keyPath + $keyName;

    try
    {
        # Get the current acl of the private key
        # This is the line that fails!
        $acl = Get-Acl -Path $keyFullPath;

        # Add the new ace to the acl of the private key
        $acl.AddAccessRule($accessRule);

        # Write back the new acl
        Set-Acl -Path $keyFullPath -AclObject $acl;
    }
    catch
    {
        throw $_;
    }
}

$cert = Get-ChildItem -Path cert:\LocalMachine\My | ?{ $_.ThumbPrint -eq "THUMBPRINT" }
if($cert) {
	$store = Get-Item $cert.PsParentPath
	$store.open('ReadWrite')
	$store.Remove($cert)
	$store.close()
}

Add-Certificate "PATH_TO_PFX" "PASSWORD" -Verbose
Set-CertificatePermission "THUMBPRINT" "SERVICE ACCOUNT" -Verbose