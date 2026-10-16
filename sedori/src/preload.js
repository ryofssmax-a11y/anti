const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("api", {
  load: () => ipcRenderer.invoke("data-load"),
  save: data => ipcRenderer.invoke("data-save", data),
  openExternal: url => ipcRenderer.invoke("open-external", url),
  saveFile: opts => ipcRenderer.invoke("save-file", opts),
  openJson: () => ipcRenderer.invoke("open-json"),
  fetchRate: () => ipcRenderer.invoke("fetch-rate"),
  ebaySearch: opts => ipcRenderer.invoke("ebay-search", opts),
});
