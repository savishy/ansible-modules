#!powershell

# Copyright: (c) 2015, Jon Hawkesworth (@jhawkesworth) <figs@unity.demon.co.uk>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#Requires -Module Ansible.ModuleUtils.Legacy

$ErrorActionPreference = "Stop"

$params = Parse-Args -arguments $args -supports_check_mode $true
$check_mode = Get-AnsibleParam -obj $params -name "_ansible_check_mode" -type "bool" -default $false
$diff_mode = Get-AnsibleParam -obj $params -name "_ansible_diff" -type "bool" -default $false

$name = Get-AnsibleParam -obj $params -name "name" -type "str" -failifempty $true
$state = Get-AnsibleParam -obj $params -name "state" -type "str" -default "present" -validateset "absent","present"
$network = Get-AnsibleParam -obj $params -name "network" -type "str"
$image = Get-AnsibleParam -obj $params -name "image" -type "str" -failifempty $true
$publish_all_ports = Get-AnsibleParam -obj $params -name "publish_all_ports" -type "bool" -default $true

$result = @{
    changed = $false
}

if ($network -ne $null) {
    $networks = $(docker network ls -q --filter "name=$($network)")
    if ($networks -eq $null) {
        Fail-Json -obj $result -message "A required docker network named $($network) was not found!"
    }
    # we only support the default nat network for windows for now.
    if ($network -ne "nat") {
        Fail-Json -obj $result -message "Only the default nat network is supported for now. Docker Network support is WIP."
    }
}
$existingContainers = $(docker ps -aq --filter "name=$($name)")
if ($existingContainers -ne $null) {
    # existing containers with the same name were found.
    if ($state -eq "present") {
        $result.container_id = $existingContainers
        $result.msg = "container already exists"
    } elseif ($state -eq "absent") {
        # we need to delete existing containers
        $command = "docker rm -f $($existingContainers)"

        $result.command = $command
        $result.container_id = $existingContainers
        $result.changed = $true
        $result.msg = "container $($existingContainers) removed"

        iex $command
    }
} else {
    if ($state -eq "present") {
        # no existing containers; create
        $networkCmd = if ($network -ne $null) { "--net $($network)" } else { "" }
        $portsCmd = if ($publish_all_ports) { "-P" } else { "" }

        $command = "docker run $($networkCmd) $($portsCmd) --name $($name) -d $($image)"
        $newContainer = iex $command

        # container access may require the IP so print that as debug info.
        $ipAddresses = (Get-WmiObject win32_NetworkAdapterConfiguration | ? {$_.IPAddress -ne $null}).IPAddress | Out-String

        $result.command = $command
        $result.changed = $true
        $result.container_id = $newContainer
        $result.msg = "container created. Use one of the following IPs to connect to it: $($ipAddresses)"

    } elseif ($state -eq "absent") {
        $result.msg = "no containers found"
    }
}


Exit-Json -obj $result
