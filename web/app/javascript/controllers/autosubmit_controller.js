import { Controller } from "@hotwired/stimulus"

// Submit a form when a control commits a change (select, checkbox, blur on text).
export default class extends Controller {
  connect() {
    this.snapshot = this.serialize()
    this.submitting = false
  }

  submit() {
    if (this.submitting) return
    if (this.serialize() === this.snapshot) return

    this.submitting = true
    this.snapshot = this.serialize()
    this.element.requestSubmit()
  }

  submitOnEnter(event) {
    if (event.key !== "Enter") return
    if (event.target.tagName === "TEXTAREA") return

    event.preventDefault()
    this.submit()
  }

  serialize() {
    return new URLSearchParams(new FormData(this.element)).toString()
  }
}
