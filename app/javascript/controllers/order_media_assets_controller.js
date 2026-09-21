import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "row", "availableSelect", "template", "removeButton", "input", "label"]

  connect() {
    this.refreshRemoveButtons()
    this.form = this.element.closest("form")
    if (this.form) {
      this.boundEnsureClip = this.ensureClip.bind(this)
      this.form.addEventListener("submit", this.boundEnsureClip, true)
    }
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.boundEnsureClip, true)
  }

  add(event) {
    event.preventDefault()
    const option = this.availableSelectTarget.selectedOptions[0]
    if (!option?.value) return

    this.appendClip(option)
  }

  ensureClip() {
    if (this.inputTargets.some((input) => input.value)) return

    const option = this.availableSelectTarget.selectedOptions[0]
    if (!option?.value) return

    this.appendClip(option)
  }

  appendClip(option) {
    const fragment = this.templateTarget.content.cloneNode(true)
    const row = fragment.querySelector("[data-order-media-assets-target='row']")
    const input = row.querySelector("[data-order-media-assets-target='input']")
    const label = row.querySelector("[data-order-media-assets-target='label']")

    input.value = option.value
    label.textContent = option.text
    row.dataset.label = option.text

    option.remove()
    this.availableSelectTarget.value = ""
    this.listTarget.appendChild(fragment)
    this.refreshRemoveButtons()
  }

  remove(event) {
    event.preventDefault()
    if (this.rowTargets.length <= 1) return

    const row = this.rowFrom(event)
    const input = row.querySelector("[data-order-media-assets-target='input']")
    const label = row.querySelector("[data-order-media-assets-target='label']")
    if (input?.value) this.restoreOption(input.value, label?.textContent || row.dataset.label || "")

    row.remove()
    this.refreshRemoveButtons()
  }

  moveUp(event) {
    event.preventDefault()
    const row = this.rowFrom(event)
    const previous = row?.previousElementSibling
    if (row && previous) {
      row.parentNode.insertBefore(row, previous)
    }
  }

  moveDown(event) {
    event.preventDefault()
    const row = this.rowFrom(event)
    const next = row?.nextElementSibling
    if (row && next) {
      row.parentNode.insertBefore(next, row)
    }
  }

  rowFrom(event) {
    return event.currentTarget.closest("[data-order-media-assets-target='row']")
  }

  restoreOption(id, label) {
    const select = this.availableSelectTarget
    const option = document.createElement("option")
    option.value = id
    option.textContent = label
    select.appendChild(option)
  }

  refreshRemoveButtons() {
    const canRemove = this.rowTargets.length > 1
    this.removeButtonTargets.forEach((button) => {
      button.disabled = !canRemove
      button.classList.toggle("btn-disabled", !canRemove)
    })
  }
}
