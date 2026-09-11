import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "overlay", "button"]

  connect() {
    this.close()
  }

  disconnect() {
    this.close()
  }

  toggle() {
    if (this.panelTarget.classList.contains("-translate-x-full")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.panelTarget.classList.remove("-translate-x-full")
    this.panelTarget.classList.add("translate-x-0")
    this.overlayTarget.classList.remove("hidden")
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.panelTarget.classList.add("-translate-x-full")
    this.panelTarget.classList.remove("translate-x-0")
    this.overlayTarget.classList.add("hidden")
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", "false")
  }
}
