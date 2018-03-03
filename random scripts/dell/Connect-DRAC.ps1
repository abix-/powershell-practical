[cmdletbinding()]
Param (
    $hostname,
    $password
)

$prefix1 = ("devqc","jaxf","jax","ord")
$prefix2 = ("copq","fakw","frow","ftfq","jxfc","jxfq-devqc","jxfq","nbiq","sfcq","sufw")
if ($hostname.indexof("rac-") -eq -1) { $hostname = "rac-" + $hostname }
$sitecode = ($hostname | Select-String "-(.*)-").matches.groups[1].value
if ($prefix1 -match $sitecode) { $username = "DRAC_ADMIN_USER1" 
} elseif ($prefix2 -match $sitecode) { $username = "DRAC_ADMIN_USER2" 
} else { $username = Read-Host "Failed to determine username. Enter username." }

$text = @"
<?xml version="1.0" encoding="UTF-8"?>
<jnlp codebase="https://EsxName:443" spec="1.0+">
<information>
  <title>iDRAC7 Virtual Console Client</title>
  <vendor>Dell Inc.</vendor>
   <icon href="https://EsxName:443/images/logo.gif" kind="splash"/>
   <shortcut online="true"/>
 </information>
 <application-desc main-class="com.avocent.idrac.kvm.Main">
   <argument>ip=EsxName</argument>
   <argument>vmprivilege=true</argument>
   <argument>helpurl=https://EsxName:443/help/contents.html</argument>
   <argument>title=EsxName</argument>
   <argument>user=$username</argument>
   <argument>passwd=$password</argument>
   <argument>kmport=5900</argument>
   <argument>vport=5900</argument>
   <argument>apcp=1</argument>
   <argument>F2=1</argument>
   <argument>F1=1</argument>
   <argument>scaling=15</argument>
   <argument>minwinheight=100</argument>
   <argument>minwinwidth=100</argument>
   <argument>videoborder=0</argument>
   <argument>version=2</argument>
 </application-desc>
 <security>
   <all-permissions/>
 </security>
 <resources>
   <j2se version="1.6+"/>
   <jar href="https://EsxName:443/software/avctKVM.jar" download="eager" main="true" />
 </resources>
 <resources os="Windows" arch="x86">
   <nativelib href="https://EsxName:443/software/avctKVMIOWin32.jar" download="eager"/>
   <nativelib href="https://EsxName:443/software/avctVMWin32.jar" download="eager"/>
 </resources>
 <resources os="Windows" arch="amd64">
   <nativelib href="https://EsxName:443/software/avctKVMIOWin64.jar" download="eager"/>
   <nativelib href="https://EsxName:443/software/avctVMWin64.jar" download="eager"/>
 </resources>
 <resources os="Windows" arch="x86_64">
   <nativelib href="https://EsxName:443/software/avctKVMIOWin64.jar" download="eager"/>
   <nativelib href="https://EsxName:443/software/avctVMWin64.jar" download="eager"/>
 </resources>
  <resources os="Linux" arch="x86">
    <nativelib href="https://EsxName:443/software/avctKVMIOLinux32.jar" download="eager"/>
   <nativelib href="https://EsxName:443/software/avctVMLinux32.jar" download="eager"/>
  </resources>
  <resources os="Linux" arch="i386">
    <nativelib href="https://EsxName:443/software/avctKVMIOLinux32.jar" download="eager"/>
   <nativelib href="https://EsxName:443/software/avctVMLinux32.jar" download="eager"/>
  </resources>
  <resources os="Linux" arch="i586">
    <nativelib href="https://EsxName:443/software/avctKVMIOLinux32.jar" download="eager"/>
   <nativelib href="https://EsxName:443/software/avctVMLinux32.jar" download="eager"/>
  </resources>
  <resources os="Linux" arch="i686">
    <nativelib href="https://EsxName:443/software/avctKVMIOLinux32.jar" download="eager"/>
   <nativelib href="https://EsxName:443/software/avctVMLinux32.jar" download="eager"/>
  </resources>
  <resources os="Linux" arch="amd64">
    <nativelib href="https://EsxName:443/software/avctKVMIOLinux64.jar" download="eager"/>
   <nativelib href="https://EsxName:443/software/avctVMLinux64.jar" download="eager"/>
  </resources>
  <resources os="Linux" arch="x86_64">
    <nativelib href="https://EsxName:443/software/avctKVMIOLinux64.jar" download="eager"/>
   <nativelib href="https://EsxName:443/software/avctVMLinux64.jar" download="eager"/>
  </resources>
</jnlp>
"@

$text = $text | % { $_ -Replace "EsxName",$hostname }
Out-File -Encoding UTF8 -FilePath "$hostname.jnlp" -InputObject $text
Invoke-Item $hostname".jnlp"
Start-Sleep -s 5
del "$hostname.jnlp"