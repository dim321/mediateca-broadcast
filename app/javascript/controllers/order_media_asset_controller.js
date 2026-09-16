import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "details", "duration", "contentType", "contentKind"]

  connect() {
    this.update()
  }

  update() {
    const option = this.selectTarget.selectedOptions[0]
    const hasAsset = option?.value

    this.detailsTarget.classList.toggle("hidden", !hasAsset)
    if (!hasAsset) return

    this.durationTarget.textContent = option.dataset.duration || "—"
    this.contentTypeTarget.textContent = option.dataset.contentType || "—"
    this.contentKindTarget.textContent = option.dataset.contentKind || "—"
  }
}
