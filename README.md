# Blueprints

## new-ng-dotnet.sh

Generates an Angular 20+ client and a .NET Web API server (WSL/Linux), ready to run and debug.

    ./new-ng-dotnet.sh MyApp [--force] [--api-port 5100] [--client-port 4200] [--browser msedge|chrome]

Requires: .NET SDK, Node.js, Angular CLI (`npm i -g @angular/cli`), curl.

### What you get
- `MyApp.Server` - .NET API on `http://localhost:5100` (controller, `/health`, ProblemDetails)
- `MyApp.Client` - Angular app (signals, OnPush) with a dev proxy for `/api`
- Scalar API docs at `/scalar` (the root URL redirects there). Always on in Development;
  elsewhere set `"Docs": { "Enabled": true }` in appsettings.
- VS Code: open the folder with `code .`, pick **Full Stack (F5)**, press F5.
  Angular waits for the API (`/health`), and Scalar opens automatically.
- `run.sh` (run without debugger) and `verify.sh` (checks API and proxy)

### Notes
- Linux paths are case-sensitive: the app name is written exactly as you type it.
- Use either F5 or `run.sh`, not both (same ports).
- Docs/Scalar are not exposed in Production unless `Docs:Enabled` is true.
