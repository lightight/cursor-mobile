import path from "node:path";
import { app, BrowserWindow, Menu, Tray, nativeImage, ipcMain, dialog } from "electron";
import QRCode from "qrcode";
import { authStatus, fetchMe } from "./auth";
import { CompanionServer, desktopLogin, desktopLogout } from "./server";

let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let server: CompanionServer | null = null;

function rendererPath(): string {
  return path.join(__dirname, "renderer", "index.html");
}

async function createWindow(): Promise<void> {
  mainWindow = new BrowserWindow({
    width: 420,
    height: 640,
    title: "Cursor Mobile Companion",
    backgroundColor: "#0b0b0c",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  await mainWindow.loadFile(rendererPath());
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

function createTray(): void {
  const image = nativeImage.createFromDataURL(
    "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAGElEQVRYR+3BMQEAAAgDINc/9K3hAxMQevEAAAD//wMAFxsC/QbP2V0AAAAASUVORK5CYII=",
  );
  tray = new Tray(image);
  const menu = Menu.buildFromTemplate([
    { label: "Open Companion", click: () => mainWindow?.show() || createWindow() },
    {
      label: "Sign in with Cursor",
      click: () => desktopLogin().catch((err) => dialog.showErrorBox("Login failed", String(err))),
    },
    { type: "separator" },
    { label: "Quit", click: () => app.quit() },
  ]);
  tray.setToolTip("Cursor Mobile Companion");
  tray.setContextMenu(menu);
}

app.whenReady().then(async () => {
  server = new CompanionServer();
  await server.start();
  ipcMain.handle("state", async () => {
    const status = await authStatus();
    const me = await fetchMe();
    const lan = `ws://localhost:${server!.port}/ws`;
    const qr = await QRCode.toDataURL(`${lan}#${server!.pairingCode}`);
    return {
      pairingCode: server!.pairingCode,
      port: server!.port,
      qr,
      auth: status,
      me,
    };
  });
  ipcMain.handle("login", () => desktopLogin());
  ipcMain.handle("logout", () => desktopLogout());
  ipcMain.handle("rotate-code", () => server!.rotateCode());
  createTray();
  await createWindow();
});

app.on("window-all-closed", () => {
  /* keep tray companion running */
});

app.on("before-quit", () => {
  server?.stop();
});
