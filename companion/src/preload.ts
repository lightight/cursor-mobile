import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("companion", {
  state: () => ipcRenderer.invoke("state"),
  login: () => ipcRenderer.invoke("login"),
  logout: () => ipcRenderer.invoke("logout"),
  rotateCode: () => ipcRenderer.invoke("rotate-code"),
});
