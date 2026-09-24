import { Controller } from "@hotwired/stimulus"

// OmniFocus .ofocus-backup looks like a file in Finder but is a folder
// (document package). A normal <input type="file"> cannot read it; drop
// and webkitdirectory can, via DirectoryEntry / relative paths.
export default class extends Controller {
  static targets = [ "form", "file", "directory", "status", "dropzone" ]

  pickFile() {
    this.fileTarget.click()
  }

  pickDirectory() {
    this.directoryTarget.click()
  }

  async fileChosen(event) {
    const file = event.target.files?.[0]
    if (!file) return
    this.setStatus(file.name)
    this.formTarget.requestSubmit()
  }

  async directoryChosen(event) {
    const files = Array.from(event.target.files || [])
    if (!files.length) return

    await this.submitBundle(
      files.map((file) => ({
        file,
        path: file.webkitRelativePath || file.name
      }))
    )
  }

  dragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("is-over")
  }

  dragLeave(event) {
    if (event.target === this.dropzoneTarget) {
      this.dropzoneTarget.classList.remove("is-over")
    }
  }

  async drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("is-over")

    const items = Array.from(event.dataTransfer?.items || [])
    const entries = items
      .map((item) => item.webkitGetAsEntry?.())
      .filter(Boolean)

    if (entries.length) {
      const collected = []
      for (const entry of entries) {
        collected.push(...await this.collectEntry(entry, ""))
      }
      if (collected.length === 1 && this.isZip(collected[0].file)) {
        this.assignFile(collected[0].file)
        this.formTarget.requestSubmit()
        return
      }
      if (collected.length) {
        await this.submitBundle(collected)
        return
      }
    }

    const file = event.dataTransfer?.files?.[0]
    if (file) {
      this.assignFile(file)
      this.formTarget.requestSubmit()
    }
  }

  assignFile(file) {
    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.fileTarget.files = transfer.files
    this.setStatus(file.name)
  }

  async submitBundle(collected) {
    this.setStatus(`Reading ${collected.length} files from the backup…`)

    const formData = new FormData()
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    collected.forEach(({ file, path }) => {
      formData.append("import_batch[bundle_files][]", file, file.name)
      formData.append("import_batch[bundle_paths][]", path)
    })

    const response = await fetch(this.formTarget.action, {
      method: "POST",
      body: formData,
      headers: {
        Accept: "text/html",
        "X-CSRF-Token": csrf
      },
      redirect: "follow"
    })

    if (response.redirected) {
      window.Turbo.visit(response.url)
      return
    }

    this.setStatus("Could not read that backup. Try dropping it again, or upload the zip inside the package.")
  }

  async collectEntry(entry, prefix) {
    const path = prefix ? `${prefix}${entry.name}` : entry.name

    if (entry.isFile) {
      const file = await new Promise((resolve, reject) => entry.file(resolve, reject))
      return [ { file, path } ]
    }

    if (!entry.isDirectory) return []

    const children = await this.readDirectory(entry)
    const collected = []
    for (const child of children) {
      collected.push(...await this.collectEntry(child, `${path}/`))
    }
    return collected
  }

  readDirectory(entry) {
    const reader = entry.createReader()
    const entries = []

    return new Promise((resolve, reject) => {
      const tick = () => {
        reader.readEntries((batch) => {
          if (!batch.length) {
            resolve(entries)
            return
          }
          entries.push(...batch)
          tick()
        }, reject)
      }
      tick()
    })
  }

  isZip(file) {
    return /\.zip$/i.test(file.name) || /\.ofocus(-backup)?$/i.test(file.name)
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
