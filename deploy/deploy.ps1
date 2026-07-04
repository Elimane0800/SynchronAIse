#Requires -Version 5.1
<#
.SYNOPSIS
  Build the SynchronAIse backend image into k3s and deploy with Helm.

.DESCRIPTION
  Verifies Rancher Desktop (kubectl context rancher-desktop), checks the
  application-collection pull secret in hackathon, builds synchronaise-backend:dev,
  and runs helm upgrade --install.

.PARAMETER Namespace
  Kubernetes namespace (default: hackathon).

.PARAMETER ReleaseName
  Helm release name (default: synchronaise).

.PARAMETER ExpectedContext
  Required kubectl context (default: rancher-desktop).

.PARAMETER ImageTag
  Local image tag to build (default: synchronaise-backend:dev).

.PARAMETER ImagePullSecret
  Name of the registry pull secret (default: application-collection).

.PARAMETER SkipBuild
  Skip the container image build step.

.PARAMETER SkipHelm
  Skip the Helm upgrade --install step.
#>
param(
    [string]$Namespace = "hackathon",
    [string]$ReleaseName = "synchronaise",
    [string]$ExpectedContext = "rancher-desktop",
    [string]$ImageTag = "synchronaise-backend:dev",
    [string]$ImagePullSecret = "application-collection",
    [switch]$SkipBuild,
    [switch]$SkipHelm
)

$ErrorActionPreference = "Stop"

function Write-Err {
    param([string]$Message)
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "OK: $Message" -ForegroundColor Green
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-KubectlResource {
    param([string[]]$KubectlArgs)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & kubectl @KubectlArgs 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Invoke-Checked {
    param(
        [string]$Label,
        [scriptblock]$Command
    )
    & $Command
    if ($LASTEXITCODE -ne 0) {
        Write-Err "$Label failed (exit code $LASTEXITCODE)."
    }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ChartPath = Join-Path $ScriptDir "helm\synchronaise"
$BackendPath = Join-Path $RepoRoot "backend"

Set-Location $RepoRoot

Write-Host ""
Write-Host "SynchronAIse deploy" -ForegroundColor White
Write-Host "===================" -ForegroundColor White
Write-Host ""

foreach ($cmd in @("kubectl", "helm")) {
    if (-not (Test-Command $cmd)) {
        Write-Err "$cmd is not installed or not in PATH."
    }
}

if (-not $SkipBuild) {
    if (-not (Test-Path $BackendPath)) {
        Write-Err "Backend directory not found at $BackendPath"
    }
    if (-not (Test-Path (Join-Path $BackendPath "Dockerfile"))) {
        Write-Err "Dockerfile not found at $BackendPath\Dockerfile"
    }
}

if (-not $SkipHelm) {
    if (-not (Test-Path $ChartPath)) {
        Write-Err "Helm chart not found at $ChartPath"
    }
}

Write-Info "Checking kubectl context..."
$currentContext = (kubectl config current-context 2>$null).Trim()
if (-not $currentContext) {
    Write-Err @"
kubectl has no current context. Is Rancher Desktop running?

  Start Rancher Desktop, then run:
    kubectl config use-context rancher-desktop
"@
}
if ($currentContext -ne $ExpectedContext) {
    Write-Err @"
kubectl context is '$currentContext', expected '$ExpectedContext'.

  kubectl config use-context $ExpectedContext
"@
}
Write-Ok "kubectl context is $ExpectedContext"

Write-Info "Checking namespace '$Namespace'..."
if (-not (Test-KubectlResource @("get", "namespace", $Namespace))) {
    Write-Err @"
Namespace '$Namespace' does not exist.

Run init.bat from the rancher-hackathon-paris repo once to bootstrap k3s,
the hackathon namespace, and the application-collection pull secret.
"@
}
Write-Ok "namespace $Namespace exists"

Write-Info "Checking image-pull secret '$ImagePullSecret'..."
if (-not (Test-KubectlResource @("get", "secret", $ImagePullSecret, "-n", $Namespace))) {
    Write-Err @"
Secret '$ImagePullSecret' not found in namespace '$Namespace'.

The hackathon bootstrap has not been applied on this machine.
Run init.bat from the rancher-hackathon-paris repo once, then retry.

That script creates:
  - kubectl context: rancher-desktop
  - namespace: hackathon
  - secret: application-collection (dp.apps.rancher.io pull credentials)
"@
}
Write-Ok "secret $ImagePullSecret exists in $Namespace"

Write-Info "Checking LLM secret 'synchronaise-llm'..."
if (-not (Test-KubectlResource @("get", "secret", "synchronaise-llm", "-n", $Namespace))) {
    Write-Host ""
    Write-Host "WARNING: Secret 'synchronaise-llm' not found. Pods will not start until it exists." -ForegroundColor Yellow
    Write-Host "  Create from backend/.env (mock mode works with empty keys):" -ForegroundColor Yellow
    Write-Host "    kubectl create secret generic synchronaise-llm --from-env-file=backend/.env -n $Namespace" -ForegroundColor Yellow
    Write-Host "  Or let Helm create it: add --set secret.create=true (and set secret.data.* keys)" -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Ok "secret synchronaise-llm exists"
}

function Get-ContainerEngine {
    if (Test-Command "rdctl") {
        try {
            $settings = rdctl list-settings 2>$null | ConvertFrom-Json
            if ($settings.containerEngine.name -eq "dockerd") {
                return "docker"
            }
            return "nerdctl"
        } catch {
            # fall through
        }
    }

    if ((Test-Command "nerdctl") -and -not (Test-Command "docker")) {
        return "nerdctl"
    }

    if (Test-Command "docker") {
        $dockerInfo = docker info 2>$null
        if ($LASTEXITCODE -eq 0) {
            return "docker"
        }
    }

    if (Test-Command "nerdctl") {
        return "nerdctl"
    }

    return $null
}

if (-not $SkipBuild) {
    Write-Info "Building image $ImageTag..."
    $engine = Get-ContainerEngine

    if ($engine -eq "docker") {
        if (-not (Test-Command "docker")) {
            Write-Err "Rancher Desktop is using dockerd but the docker CLI is not in PATH."
        }
        Write-Info "Using docker build (dockerd engine)..."
        Invoke-Checked "docker build" { docker build -t $ImageTag $BackendPath }
    } elseif ($engine -eq "nerdctl") {
        Write-Info "Using nerdctl build (containerd / k8s.io namespace)..."
        Invoke-Checked "nerdctl build" { nerdctl --namespace k8s.io build -t $ImageTag $BackendPath }
    } else {
        Write-Err @"
No container build tool found. Install nerdctl or docker, or enable a container
engine in Rancher Desktop (Container Engine -> containerd or dockerd).
"@
    }

    Write-Ok "image built: $ImageTag"
}

if (-not $SkipHelm) {
    Write-Info "Running helm upgrade --install $ReleaseName..."
    Invoke-Checked "helm upgrade --install" {
        helm upgrade --install $ReleaseName $ChartPath `
            --namespace $Namespace `
            --set "global.imagePullSecrets={$ImagePullSecret}"
    }
    Write-Ok "Helm release '$ReleaseName' deployed to namespace '$Namespace'"
}

Write-Host ""
Write-Host "Deploy complete." -ForegroundColor Green
Write-Host ""
Write-Host "Forward the service to your machine:" -ForegroundColor Yellow
Write-Host "  kubectl port-forward -n $Namespace svc/$ReleaseName 8080:8080"
Write-Host ""
Write-Host "Then verify:" -ForegroundColor Yellow
Write-Host "  curl http://localhost:8080/healthz"
Write-Host ""
