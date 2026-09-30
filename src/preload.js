const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("api", {
  listSources: () => ipcRenderer.invoke("list-sources"),
  setCapture: opts => ipcRenderer.invoke("set-capture", opts),
  recStart: () => ipcRenderer.invoke("rec-start"),
  recChunk: buf => ipcRenderer.invoke("rec-chunk", buf),
  recFinish: () => ipcRenderer.invoke("rec-finish"),
  recDiscard: () => ipcRenderer.invoke("rec-discard"),
  showInFolder: p => ipcRenderer.invoke("show-in-folder", p),
});
