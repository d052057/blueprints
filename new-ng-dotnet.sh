#!/usr/bin/env bash
# new-ng-dotnet.sh - Angular (20+) + .NET Web API blueprint for WSL
# Usage: ./new-ng-dotnet.sh <AppName> [--force] [--api-port 5100] [--client-port 4200] [--browser msedge|chrome]
set -euo pipefail

usage() {
  echo "Usage: $0 <AppName> [--force] [--api-port 5100] [--client-port 4200] [--browser msedge|chrome]"
  exit 1
}

# ---------------------------------------------------------------- config
APP_NAME=""; FORCE=0; API_PORT=5100; CLIENT_PORT=4200; DOTNET_TFM="net10.0"; BROWSER="msedge"
while [ $# -gt 0 ]; do
  case "$1" in
    --force)       FORCE=1 ;;
    --api-port)    API_PORT="${2:?missing value}"; shift ;;
    --client-port) CLIENT_PORT="${2:?missing value}"; shift ;;
    --browser)     BROWSER="${2:?missing value}"; shift ;;
    -h|--help)     usage ;;
    -*)            echo "Unknown option: $1"; usage ;;
    *)             APP_NAME="$1" ;;
  esac
  shift
done
[ -n "$APP_NAME" ] || usage
[[ "$BROWSER" =~ ^(msedge|chrome)$ ]] || { echo "❌ --browser must be msedge or chrome"; exit 1; }
[[ "$APP_NAME" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || {
  echo "❌ AppName must start with a letter and contain only letters, digits, underscore."; exit 1; }

# ---------------------------------------------------------------- tools
need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ '$1' not found. $2"; exit 1; }; }
need dotnet "Install the .NET SDK."
need node   "Install Node.js (LTS)."
need npm    "Install Node.js (LTS)."
need ng     "npm install -g @angular/cli"
need curl   "sudo apt install curl"
echo "dotnet $(dotnet --version) | node $(node --version) | npm $(npm --version)"

# ---------------------------------------------------------------- paths (all absolute)
ROOT_DIR="$(pwd)/$APP_NAME"
SERVER_DIR="$ROOT_DIR/${APP_NAME}.Server"
CLIENT_DIR="$ROOT_DIR/${APP_NAME}.Client"

if [ -e "$ROOT_DIR" ]; then
  [ "$FORCE" = 1 ] || { echo "❌ $ROOT_DIR already exists. Re-run with --force to replace it."; exit 1; }
  rm -rf "$ROOT_DIR"
fi
mkdir -p "$ROOT_DIR"

echo "🚀 Generating $APP_NAME  (API http://localhost:$API_PORT, client http://localhost:$CLIENT_PORT)"

# ================================================================ 1. BACKEND
dotnet new webapi -o "$SERVER_DIR" --framework "$DOTNET_TFM" --no-https
mkdir -p "$SERVER_DIR/Controllers" "$SERVER_DIR/Properties"

cat << 'JSON_EOF' > "$SERVER_DIR/appsettings.json"
{
  "Logging": { "LogLevel": { "Default": "Information", "Microsoft.AspNetCore": "Warning" } },
  "AllowedHosts": "*"
}
JSON_EOF

# NOTE: placeholder connection strings - replace before real use.
cat << 'JSON_EOF' > "$SERVER_DIR/appsettings.Local.json"
{
  "ConnectionStrings": { "DefaultConnection": "Server=localhost\\SQLEXPRESS;Database=__APP__Db;Trusted_Connection=True;TrustServerCertificate=True;" },
  "Storage": { "Medias": "C:\\medias" }
}
JSON_EOF

cat << 'JSON_EOF' > "$SERVER_DIR/appsettings.Linux.json"
{
  "ConnectionStrings": { "DefaultConnection": "Server=tcp:127.0.0.1,1433;Database=__APP__Db;User Id=sa;Password=CHANGE_ME;TrustServerCertificate=True;" },
  "Storage": { "Medias": "/mnt/medias" }
}
JSON_EOF

# Single source of truth for the API port.
cat << 'JSON_EOF' > "$SERVER_DIR/Properties/launchSettings.json"
{
  "$schema": "https://json.schemastore.org/launchsettings.json",
  "profiles": {
    "http": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": false,
      "applicationUrl": "http://localhost:__API_PORT__",
      "environmentVariables": { "ASPNETCORE_ENVIRONMENT": "Development" }
    }
  }
}
JSON_EOF

cat << 'CTRL_EOF' > "$SERVER_DIR/Controllers/WeatherForecastController.cs"
using Microsoft.AspNetCore.Mvc;

namespace __APP__.Server.Controllers;

[ApiController]
[Route("api/[controller]")]
public class WeatherForecastController : ControllerBase
{
    private static readonly string[] Summaries =
    {
        "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
    };

    [HttpGet]
    public IEnumerable<WeatherForecast> Get() =>
        Enumerable.Range(1, 5).Select(index => new WeatherForecast
        {
            Date = DateOnly.FromDateTime(DateTime.Now.AddDays(index)).ToString("yyyy-MM-dd"),
            TemperatureC = Random.Shared.Next(-20, 55),
            Summary = Summaries[Random.Shared.Next(Summaries.Length)]
        }).ToArray();
}

public class WeatherForecast
{
    public string Date { get; set; } = string.Empty;
    public int TemperatureC { get; set; }
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
    public string Summary { get; set; } = string.Empty;
}
CTRL_EOF

cat << 'CS_EOF' > "$SERVER_DIR/Program.cs"
using System.Runtime.InteropServices;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

// Keep the default sources, then layer the platform file on top and restore precedence.
var platformFile = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
    ? "appsettings.Local.json"
    : "appsettings.Linux.json";
builder.Configuration.AddJsonFile(platformFile, optional: true, reloadOnChange: true);
builder.Configuration.AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true);
builder.Configuration.AddEnvironmentVariables();
builder.Configuration.AddCommandLine(args);

builder.Services
    .AddControllers()
    .AddJsonOptions(o =>
    {
        o.JsonSerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
        o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
    });
builder.Services.AddProblemDetails();
builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();            // /openapi/v1.json
}
else
{
    app.UseExceptionHandler();
    app.UseHttpsRedirection();
}

app.UseAuthorization();
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapControllers();

app.Run();
CS_EOF

# ================================================================ 2. FRONTEND
( cd "$ROOT_DIR" && ng new "${APP_NAME}.Client" --routing --style scss --ssr false \
    --skip-install --skip-git --defaults )

[ -f "$CLIENT_DIR/src/app/app.ts" ] || {
  echo "❌ src/app/app.ts not found. This blueprint expects Angular 20+ (check: ng version)."; exit 1; }

( cd "$CLIENT_DIR" && npm install bootstrap bootstrap-icons --silent )

# Proxy file lives NEXT TO angular.json (not in src/).
cat << PROXY_EOF > "$CLIENT_DIR/proxy.conf.json"
{
  "/api": {
    "target": "http://127.0.0.1:${API_PORT}",
    "secure": false,
    "changeOrigin": true,
    "logLevel": "info"
  }
}
PROXY_EOF

# Patch angular.json with Node (no fragile sed): proxy, port, bootstrap-icons css.
CLIENT_DIR="$CLIENT_DIR" CLIENT_PORT="$CLIENT_PORT" node - << 'NODE_EOF'
const fs = require("fs");
const path = require("path");
const file = path.join(process.env.CLIENT_DIR, "angular.json");
const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
const icons = "node_modules/bootstrap-icons/font/bootstrap-icons.css";
for (const p of Object.values(cfg.projects)) {
  const a = p.architect || {};
  if (a.serve) {
    a.serve.options = a.serve.options || {};
    a.serve.options.proxyConfig = "proxy.conf.json";
    a.serve.options.port = Number(process.env.CLIENT_PORT);
  }
  if (a.build) {
    a.build.options = a.build.options || {};
    const styles = (a.build.options.styles = a.build.options.styles || []);
    if (!styles.includes(icons)) styles.push(icons);
  }
}
fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
NODE_EOF

echo '@use "bootstrap/scss/bootstrap";' > "$CLIENT_DIR/src/styles.scss"
rm -f "$CLIENT_DIR/src/app/app.spec.ts"

cat << 'TS_EOF' > "$CLIENT_DIR/src/main.ts"
import { bootstrapApplication } from '@angular/platform-browser';
import { provideHttpClient } from '@angular/common/http';
import { provideRouter } from '@angular/router';
import { App } from './app/app';
import { routes } from './app/app.routes';

bootstrapApplication(App, {
  providers: [provideHttpClient(), provideRouter(routes)]
}).catch(err => console.error(err));
TS_EOF

# Signals + OnPush: works with or without zone.js.
cat << 'TS_EOF' > "$CLIENT_DIR/src/app/app.ts"
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';

interface WeatherForecast {
  date: string;
  temperatureC: number;
  temperatureF: number;
  summary: string;
}

@Component({
  selector: 'app-root',
  templateUrl: './app.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class App implements OnInit {
  private readonly http = inject(HttpClient);

  readonly forecasts = signal<WeatherForecast[]>([]);
  readonly loading = signal(true);
  readonly error = signal<string | null>(null);

  ngOnInit() {
    this.load();
  }

  load() {
    this.loading.set(true);
    this.error.set(null);
    this.http.get<WeatherForecast[]>('/api/weatherforecast').subscribe({
      next: (result) => {
        this.forecasts.set(result);
        this.loading.set(false);
      },
      error: (err: HttpErrorResponse) => {
        console.error('API error:', err);
        this.error.set(
          err.status === 200
            ? '200 but not JSON - the dev proxy is probably not active.'
            : `${err.status} ${err.statusText || 'Request failed'}`
        );
        this.loading.set(false);
      }
    });
  }
}
TS_EOF

cat << 'HTML_EOF' > "$CLIENT_DIR/src/app/app.html"
<nav class="navbar navbar-expand-lg navbar-dark bg-dark shadow-sm">
  <div class="container">
    <a class="navbar-brand d-flex align-items-center fw-bold" href="#">
      <i class="bi bi-cpu-fill me-2 text-info"></i>FullStack Application
    </a>
  </div>
</nav>

<div class="container mt-5">
  <div class="p-4 p-md-5 mb-4 bg-light rounded-3 border shadow-sm">
    <h1 class="display-6 fw-bold text-primary"><i class="bi bi-activity me-2"></i>Controller Architecture</h1>
    <p class="text-muted mb-0">Data served by a .NET controller and reached through the Angular dev proxy.</p>
  </div>

  <div class="card shadow border-0">
    <div class="card-header bg-secondary text-white py-3 d-flex justify-content-between align-items-center">
      <h6 class="mb-0 fw-semibold"><i class="bi bi-calendar3 me-2"></i>Live Server Telemetry</h6>
      <button class="btn btn-sm btn-light" (click)="load()" [disabled]="loading()">
        <i class="bi bi-arrow-clockwise"></i> Refresh
      </button>
    </div>
    <div class="card-body p-0">
      @if (loading()) {
        <div class="text-center p-5">
          <div class="spinner-border text-primary" role="status"></div>
          <p class="mt-3 text-muted">Awaiting response from backend...</p>
        </div>
      } @else if (error()) {
        <div class="alert alert-danger m-3 d-flex justify-content-between align-items-center">
          <span>Failed to load data: {{ error() }}</span>
          <button class="btn btn-sm btn-outline-danger" (click)="load()">Retry</button>
        </div>
      } @else {
        <table class="table table-striped table-hover mb-0 align-middle">
          <thead class="table-light">
            <tr><th>Target Date</th><th>Celsius</th><th>Fahrenheit</th><th>Summary</th></tr>
          </thead>
          <tbody>
            @for (f of forecasts(); track f.date) {
              <tr>
                <td class="text-secondary fw-semibold">{{ f.date }}</td>
                <td><span class="badge bg-info text-dark px-3 py-2 fs-6">{{ f.temperatureC }}°C</span></td>
                <td><span class="badge bg-warning text-dark px-3 py-2 fs-6">{{ f.temperatureF }}°F</span></td>
                <td><span class="text-dark font-monospace fw-medium">{{ f.summary }}</span></td>
              </tr>
            }
          </tbody>
        </table>
      }
    </div>
  </div>
</div>
HTML_EOF

# ================================================================ 3. TOOLING
mkdir -p "$ROOT_DIR/.vscode"

cat << 'JSON_EOF' > "$ROOT_DIR/.vscode/tasks.json"
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build-api",
      "type": "process",
      "command": "dotnet",
      "args": ["build", "${workspaceFolder}/__APP__.Server"],
      "problemMatcher": "$msCompile"
    },
    {
      "label": "ng-serve",
      "type": "shell",
      "command": "npm start",
      "options": { "cwd": "${workspaceFolder}/__APP__.Client" },
      "isBackground": true,
      "problemMatcher": {
        "owner": "angular",
        "pattern": "$tsc",
        "background": {
          "activeOnStart": true,
          "beginsPattern": "Initial chunk files|Changes detected",
          "endsPattern": "Local:|Failed to compile"
        }
      }
    }
  ]
}
JSON_EOF

# F5 = debug API (coreclr) + Angular (browser) together.
cat << 'JSON_EOF' > "$ROOT_DIR/.vscode/launch.json"
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": ".NET API",
      "type": "coreclr",
      "request": "launch",
      "preLaunchTask": "build-api",
      "program": "${workspaceFolder}/__APP__.Server/bin/Debug/__TFM__/__APP__.Server.dll",
      "cwd": "${workspaceFolder}/__APP__.Server",
      "env": {
        "ASPNETCORE_ENVIRONMENT": "Development",
        "ASPNETCORE_URLS": "http://localhost:__API_PORT__"
      },
      "console": "internalConsole"
    },
    {
      "name": "Angular (__BROWSER__)",
      "type": "__BROWSER__",
      "request": "launch",
      "preLaunchTask": "ng-serve",
      "url": "http://localhost:__CLIENT_PORT__",
      "webRoot": "${workspaceFolder}/__APP__.Client"
    }
  ],
  "compounds": [
    {
      "name": "Full Stack (F5)",
      "configurations": [".NET API", "Angular (__BROWSER__)"],
      "stopAll": true,
      "presentation": { "order": 1 }
    }
  ]
}
JSON_EOF

cat << 'JSON_EOF' > "$ROOT_DIR/.vscode/extensions.json"
{
  "recommendations": [
    "ms-dotnettools.csdevkit",
    "angular.ng-template"
  ]
}
JSON_EOF

cat << 'SH_EOF' > "$ROOT_DIR/run.sh"
#!/usr/bin/env bash
# Starts API + Angular together. Ctrl+C stops both.
set -euo pipefail
cd "$(dirname "$0")"
trap 'trap - EXIT INT TERM; kill 0' EXIT INT TERM
( cd __APP__.Server && dotnet run --launch-profile http ) &
( cd __APP__.Client && npm start ) &
wait
SH_EOF

cat << 'SH_EOF' > "$ROOT_DIR/verify.sh"
#!/usr/bin/env bash
# Starts both apps and checks: API direct, then API through the Angular proxy.
set -euo pipefail
cd "$(dirname "$0")"
API="http://127.0.0.1:__API_PORT__"
WEB="http://127.0.0.1:__CLIENT_PORT__"
LOG="$(mktemp -d)"
trap 'trap - EXIT INT TERM; kill 0' EXIT INT TERM

wait_json() {  # url, seconds
  for _ in $(seq 1 "$2"); do
    if curl -fsS -o /dev/null -D - "$1" 2>/dev/null | grep -qi '^content-type:.*json'; then return 0; fi
    sleep 1
  done
  return 1
}

[ -f __APP__.Client/proxy.conf.json ] || { echo "❌ proxy.conf.json missing next to angular.json"; exit 1; }
grep -q proxyConfig __APP__.Client/angular.json || { echo "❌ proxyConfig not set in angular.json"; exit 1; }

( cd __APP__.Server && dotnet run --launch-profile http > "$LOG/api.log" 2>&1 ) &
wait_json "$API/health" 90 || { echo "❌ API did not start. See $LOG/api.log"; exit 1; }
wait_json "$API/api/weatherforecast" 10 || { echo "❌ API endpoint did not return JSON"; exit 1; }
echo "✅ API direct OK"

( cd __APP__.Client && npm start > "$LOG/web.log" 2>&1 ) &
wait_json "$WEB/api/weatherforecast" 180 || {
  echo "❌ Proxy check failed (got HTML or nothing). See $LOG/web.log"; exit 1; }
echo "✅ Angular proxy OK - open $WEB"
SH_EOF

cat << 'GI_EOF' > "$ROOT_DIR/.gitignore"
bin/
obj/
node_modules/
.angular/
dist/
.vs/
*.db
*.user
GI_EOF

# Replace placeholders in generated files that use them.
sed -i "s/__APP__/${APP_NAME}/g; s/__API_PORT__/${API_PORT}/g; s/__CLIENT_PORT__/${CLIENT_PORT}/g; s/__TFM__/${DOTNET_TFM}/g; s/__BROWSER__/${BROWSER}/g" \
  "$SERVER_DIR/appsettings.Local.json" \
  "$SERVER_DIR/appsettings.Linux.json" \
  "$SERVER_DIR/Properties/launchSettings.json" \
  "$SERVER_DIR/Controllers/WeatherForecastController.cs" \
  "$ROOT_DIR/.vscode/tasks.json" \
  "$ROOT_DIR/.vscode/launch.json" \
  "$ROOT_DIR/run.sh" \
  "$ROOT_DIR/verify.sh"
chmod +x "$ROOT_DIR/run.sh" "$ROOT_DIR/verify.sh"

# ================================================================ 4. SELF-CHECKS
echo "🔎 Self-checks..."
[ -f "$CLIENT_DIR/proxy.conf.json" ]            || { echo "❌ proxy.conf.json missing"; exit 1; }
grep -q '"proxyConfig"' "$CLIENT_DIR/angular.json" || { echo "❌ proxyConfig missing in angular.json"; exit 1; }
grep -q "$API_PORT" "$CLIENT_DIR/proxy.conf.json"  || { echo "❌ proxy target port mismatch"; exit 1; }
grep -q "$API_PORT" "$SERVER_DIR/Properties/launchSettings.json" || { echo "❌ launchSettings port mismatch"; exit 1; }
[ -f "$ROOT_DIR/.vscode/launch.json" ] || { echo "❌ launch.json missing"; exit 1; }
! grep -q "__[A-Z_]*__" "$ROOT_DIR/.vscode/launch.json" "$ROOT_DIR/.vscode/tasks.json" || { echo "❌ unreplaced placeholder in .vscode"; exit 1; }
dotnet build "$SERVER_DIR" -nologo -v q

echo "✨ $APP_NAME generated."
echo "   Run:    cd $APP_NAME && ./run.sh"
echo "   Verify: cd $APP_NAME && ./verify.sh"
echo "   Debug:  cd $APP_NAME && code .   then press F5 (Full Stack)"
