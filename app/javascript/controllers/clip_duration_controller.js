import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "warning"]
  static values = { current: Number }

  connect() {
    this.sync()
  }

  change() {
    this.sync()
  }

  disconnect() {
    if (this.hasWarningTarget) this.warningTarget.hidden = false
  }

  sync() {
    if (!this.hasSelectTarget || !this.hasWarningTarget) return

    const option = this.selectTarget.selectedOptions[0]
    const duration = Number(option?.dataset?.duration)
    const differs = Number.isFinite(duration) && duration !== this.currentValue
    this.warningTarget.hidden = !differs
  }
}
