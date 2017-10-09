#Set-PSDebug -trace 2
# Script that tests Docker on Windows functionality
Param(
    [string]$isDebug='no' 
)

$ErrorActionPreference = "Stop"
$WORK_PATH = Split-Path -parent $MyInvocation.MyCommand.Definition
$CONFIGS_PATH = $WORK_PATH + "\configs\"
$CONTAINER_NAME = "container1"
$CONTAINER_IMAGE = "nginx"
$CONTAINER_PORT = 80
$NODE_PORT = 8080
$VOLUME_NAME = "vol1"
$NETWORK_NAME = "net1"
$HOST_IP = 10.7.1.12

Import-Module "$WORK_PATH\DockerUtils"

class DockerFunctionalityTime
{
    # Optionally, add attributes to prevent invalid values
    [ValidateNotNullOrEmpty()][int]$PullImageTime
    [ValidateNotNullOrEmpty()][int]$CreateVolumeTime
    [ValidateNotNullOrEmpty()][int]$CreateNetworkTime
    [ValidateNotNullOrEmpty()][int]$BuildContainerTime
}

class DockerOperationTime
{
    # Optionally, add attributes to prevent invalid values
    [ValidateNotNullOrEmpty()][int]$PullImageTime
    [ValidateNotNullOrEmpty()][int]$CreateContainerTime
    [ValidateNotNullOrEmpty()][int]$StartContainerTime
    [ValidateNotNullOrEmpty()][int]$ExecProcessInContainerTime
    [ValidateNotNullOrEmpty()][int]$StopContainerTime
    [ValidateNotNullOrEmpty()][int]$RunContainerTime
    [ValidateNotNullOrEmpty()][int]$RemoveContainerTime
    [ValidateNotNullOrEmpty()][int]$RemoveImageTime
}

function New-Image {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$imageName
    )

    $time = Start-ExternalCommand -ScriptBlock { docker pull $imageName } `
    -ErrorMessage "`nFailed to pull docker image with $LastExitCode`n"

    Write-DebugMessage $isDebug -Message "Image pulled SUCCSESSFULLY"

    #$imageID = docker images $imageName --format "{{.ID}}"
    return [int]$time
}

function Create-Container {
    # Container can be created with or without volumes or ports exposed
    Param(
        [Parameter(Mandatory=$true)]
        [string]$containerName,
        [Parameter(Mandatory=$true)]
        [string]$containerImage,
        [switch]$exposePorts,
        [int]$nodePort,
        [int]$containerPort,
        [switch]$attachVolume,
        [string]$volumeName,
        [switch]$bindMount,
        [string]$mountPath
    )

    #Start-ExternalCommand -ScriptBlock { docker pull $containerImage } `
    #-ErrorMessage "`nFailed to pull docker image`n"

    $params = @("--name", $containerName, $containerImage)

    if($exposePorts) {
        $params = ("-p", "$nodePort`:$containerPort") + $params
    }

    if($attachVolume) {
        $params = ("-v", "$volumeName`:/data") + $params
    }

    if($bindMount) {
        $params = ("-v", "$mountPath`:/data") + $params
    }

    $time = Start-ExternalCommand -ScriptBlock { docker create $params } `
    -ErrorMessage "`nFailed to create container with $LastExitCode`n"

    Write-DebugMessage $isDebug -Message "Container created SUCCSESSFULLY"

    #$containerID = docker container inspect $containerName --format "{{.ID}}"
    return [int]$time
}

function Start-Container {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$containerName
    )

    $time = Start-ExternalCommand -ScriptBlock { docker start $containerName } `
    -ErrorMessage "`nFailed to start container with $LastExitCode`n"
    
    Write-DebugMessage $isDebug -Message "Container started SUCCSESSFULLY"

    return [int]$time
}

function Exec-Command {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$containerName
    )

    # Check if a command can be succsessfully run in a container
    $time = Start-ExternalCommand -ScriptBlock { docker exec $containerName ls } `
    -ErrorMessage "`nFailed to exec command with $LastExitCode`n"

    Write-DebugMessage $isDebug -Message "Exec runned SUCCSESSFULLY"

    return [int]$time
}

function Stop-Container {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$containerName
    )

    $time = Start-ExternalCommand -ScriptBlock { docker stop $containerName } `
    -ErrorMessage "`nFailed to stop container with $LastExitCode`n"
    Write-DebugMessage $isDebug -Message "Container stopped SUCCSESSFULLY"

    return [int]$time
}

function Remove-Container {
    Param(
        [string]$containerName
    )

    $time = Start-ExternalCommand -ScriptBlock { docker rm $containerName } `
    -ErrorMessage "`nFailed to remove container with $LastExitCode`n"

    Write-DebugMessage $isDebug -Message "Container removed SUCCSESSFULLY"

    return [int]$time
}

function Remove-Image {
    Param(
        [string]$containerImage
    )

    $time = Start-ExternalCommand -ScriptBlock { docker rmi $containerImage } `
    -ErrorMessage "`nFailed to remove image with $LastExitCode`n"

    Write-DebugMessage $isDebug -Message "Image removed SUCCSESSFULLY"

    return [int]$time
}

function New-Volume {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$volumeName
    )

    $time = Start-ExternalCommand -ScriptBlock { docker volume create $volumeName } `
    -ErrorMessage "`nFailed to create docker volume with $LastExitCode`n"

    Write-DebugMessage $isDebug -Message "Volume created SUCCSESSFULLY"

    # docker does not asign an ID to volume so cannot return one
    return [int]$time
}

function New-Network {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$networkName
    )

    # driver type is 'nat', bridge equivalent for Linux
    $time = Start-ExternalCommand -ScriptBlock { docker network create -d nat $networkName } `
    -ErrorMessage "`nFailed to create network with $LastExitCode`n"

    Write-DebugMessage $isDebug -Message "Network created SUCCSESSFULLY"

    #$networkID = docker network inspect $networkName --format "{{.ID}}"
    return [int]$time
}

function Get-HTTPGet {
    # Check if the container responds on 8080
    $res = Invoke-WebRequest -Uri http://10.7.1.12:8080
    if ($res.StatusCode -gt 400) {
        throw "`nContainer did NOT respond to HTTP GET`n"
        exit
    } else {
        Write-DebugMessage $isDebug -Message "Container responded to HTTP GET SUCCSESSFULLY"
    }
}

function Get-Attribute {
    # get the attributes of a container, network, volume
        Param
    (
        [ValidateSet("container", "network", "volume", "image")]
        [string]$elementType,
        [string]$elementName,
        [string]$attribute
    )

    $attribute = Start-ExternalCommand -ScriptBlock { docker $elementType inspect `
    $elementName --format "{{.$attribute}}"} `
    -ErrorMessage "`nCould not get attributes of $elementType $elementName"

    return $attribute
}

function Get-SharedVolume {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$containerName
    )
    # Check if data in the shared volume is accessible 
    # from containers mountpoint
    $volumeData = docker exec $containerName ls /data
    if(!$volumeData) {
        throw "`nCannot access shared volume`n"
        
    } else {
        Write-DebugMessage $isDebug -Message "Container shared volume accessed SUCCSESSFULLY"
    }
}

function Connect-Network {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$networkName,
        [Parameter(Mandatory=$true)]
        [string]$containerName
    )

    New-Network $networkName

    Start-ExternalCommand -ScriptBlock { docker network connect $networkName $containerName } `
    -ErrorMessage "`nFailed to connect network to container with $LastExitCode`n"

    Write-DebugMessage $isDebug -Message "Network connected SUCCSESSFULLY"
}

function Clear-Environment {
    # Delete existing containers, volumes or images if any
    if($(docker ps -a -q).count -ne 0) {
        docker stop $(docker ps -a -q)
        docker rm $(docker ps -a -q)  
    }

    if($(docker volume list -q).count -ne 0) {
        docker volume rm $(docker volume list -q)
    }

    if ($(docker images -a -q).count -ne 0) {
        docker rmi -f (docker images -a -q)
    }

    docker network prune --force

    Write-DebugMessage $isDebug -Message "Cleanup SUCCSESSFULL"
}

function Test-Restart {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$containerName
    )
    # Restart container and see if all the functionalities
    # are available
    $time = Start-ExternalCommand -ScriptBlock { docker restart $containerName } `
    -ErrorMessage "`nFailed to restart container with $LastExitCode`n"

    Write-DebugMessage $isDebug -Message "Restart container tests ran SUCCSESSFULLY"
    return [int]$time
}

function Test-Building {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$containerName,
        [Parameter(Mandatory=$true)]
        [string]$containerImage,
        [Parameter(Mandatory=$true)]
        [string]$configPath
    )

    (Get-Content "$configPath\Dockerfile").replace('image', $containerImage) `
    | Set-Content "$configPath\Dockerfile"

    $time = Start-ExternalCommand -ScriptBlock { docker build -f "$configPath\Dockerfile" -t $containerName . } `
    -ErrorMessage "`nFailed to build docker image with $LastExitCode`n"

    #Start-Sleep -s 5

    docker stop $containerName
    docker rm $containerName

    Write-DebugMessage $isDebug -Message "Container built SUCCSESSFULLY"
    return [int]$time
}

function Test-BasicFunctionality {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$volumeName,
        [Parameter(Mandatory=$true)]
        [string]$imageName,
        [Parameter(Mandatory=$true)]
        [string]$networkName,
        [Parameter(Mandatory=$true)]
        [string]$containerName,
        [Parameter(Mandatory=$true)]
        [string]$configPath
    )

    $FunctionalityTime = [DockerFunctionalityTime]@{
                    PullImageTime = 0
                    CreateVolumeTime = 0
                    CreateNetworkTime = 0
                    BuildContainerTime = 0
                    }

    Write-Output "`n============Starting functionality tests===============`n"
    
    # Run the functionalities tests, no containers yet
    $FunctionalityTime.PullImageTime  = New-Image $imageName
    $FunctionalityTime.CreateVolumeTime = New-Volume $volumeName
    $FunctionalityTime.CreateNetworkTime = New-Network $networkName
    $FunctionalityTime.BuildContainerTime = Test-Building $containerName $imageName $configPath

    Write-Host "`n------------------------------------------"
    Write-Host " Test result for functionality tests in ms:"
    Write-Host "------------------------------------------"

    $FunctionalityTime | Format-Table


    Clear-Environment

    Write-Output "`n============Functionality tests PASSED===============`n"
}

function Test-Container {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$containerName,
        [Parameter(Mandatory=$true)]
        [string]$containerImage,
        [Parameter(Mandatory=$true)]
        [int]$nodePort,
        [Parameter(Mandatory=$true)]
        [int]$containerPort,
        [Parameter(Mandatory=$true)]
        [string]$configPath,
        [Parameter(Mandatory=$true)]
        [string]$networkName
    )

    $OperationTime = [DockerOperationTime]@{
                    PullImageTime = 0
                    CreateContainerTime = 0
                    StartContainerTime = 0
                    ExecProcessInContainerTime = 0
                    StopContainerTime = 0
                    RunContainerTime = 0
                    RemoveContainerTime = 0
                    RemoveImageTime = 0
                    }

    Write-Output "`n============Starting create container tests===============`n"

    $OperationTime.PullImageTime = New-Image $containerImage
    $OperationTime.CreateContainerTime = Create-Container -containerName `
    $containerName -containerImage $containerImage `
    -exposePorts -nodePort $nodePort -containerPort $containerPort `
    -bindMount -mountPath $configPath
    $OperationTime.StartContainerTime = Start-Container $containerName
    $OperationTime.ExecProcessInContainerTime = Exec-Command $containerName
    $OperationTime.StopContainerTime = Stop-Container $containerName
    $OperationTime.RemoveContainerTime = Remove-Container $containerName
    $OperationTime.RemoveImageTime = Remove-Image $containerImage

    # Execute functionality tests
    #Get-Command $containerName
    #Get-HTTPGet
    #Get-SharedVolume $containerName
    #Test-Restart $containerName

    # windows does not support connecting a running container to a network
    #docker stop $containerName
    #Connect-Network $networkName $containerName

    #$created = Get-Attribute container $containerName Created
    #Write-Output $created

    #Write-Output "`n============Create container tests PASSED===============`n"

    # Cleanup container
    #Clear-Environment
    Write-Host "`n------------------------------------------"
    Write-Host " Test result for container tests in ms:"
    Write-Host "------------------------------------------"

    $OperationTime | Format-Table
}

$env:PATH = "C:\Users\dan\go\src\github.com\docker\docker\bundles\;" + $env:PATH
# execution starts here
cls

$dockerVersion = docker version
Write-Output $dockerVersion

Clear-Environment

Test-BasicFunctionality $VOLUME_NAME $CONTAINER_IMAGE $NETWORK_NAME $CONTAINER_NAME $CONFIGS_PATH
Test-Container $CONTAINER_NAME $CONTAINER_IMAGE $NODE_PORT $CONTAINER_PORT $CONFIGS_PATH $NETWORK_NAME

Write-Output "`n============All tests PASSED===============`n"