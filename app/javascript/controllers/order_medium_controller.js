import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["radio", "warning", "clipCheckbox", "screenCheckbox"]

  connect() {
    const medium = this.currentMedium()
    if (medium) this.applyMedium(medium, { showWarning: false })
  }

  changed(event) {
    this.applyMedium(event.target.value, { showWarning: true })
  }

  currentMedium() {
    const selected = this.radioTargets.find((radio) => radio.checked)
    return selected?.value
  }

  applyMedium(medium, { showWarning }) {
    let cleared = false

    this.clipCheckboxTargets.forEach((input) => {
      const kind = input.dataset.contentKind
      const ok = this.clipMatchesMedium(kind, medium)
      if (!ok && input.value) {
        this.clearClipInput(input)
        cleared = true
      }
    })

    this.screenCheckboxTargets.forEach((input) => {
      const row = input.closest("tr")
      const screenMedium = input.dataset.stationMedium
      const visible = !screenMedium || screenMedium === medium
      if (row) row.classList.toggle("hidden", !visible)

      if (screenMedium && screenMedium !== medium && input.checked) {
        input.checked = false
        input.dispatchEvent(new Event("change", { bubbles: true }))
        cleared = true
      }
    })

    this.filterAvailableClipOptions(medium)

    if (this.hasWarningTarget) {
      if (showWarning && cleared) {
        this.warningTarget.classList.remove("hidden")
      } else if (!cleared) {
        this.warningTarget.classList.add("hidden")
      }
    }
  }

  clipMatchesMedium(kind, medium) {
    return medium === "audio" ? kind === "audio" : kind !== "audio"
  }

  clearClipInput(input) {
    const row = input.closest("[data-order-media-assets-target='row']")
    if (!row) {
      input.value = ""
      return
    }

    const label = row.querySelector("[data-order-media-assets-target='label']")
    const select = this.element.querySelector("[data-order-media-assets-target='availableSelect']")
    if (select && input.value) {
      const option = document.createElement("option")
      option.value = input.value
      option.textContent = label?.textContent || row.dataset.label || ""
      option.dataset.contentKind = input.dataset.contentKind || ""
      select.appendChild(option)
    }

    row.remove()
    this.refreshClipRemoveButtons()
  }

  filterAvailableClipOptions(medium) {
    const select = this.element.querySelector("[data-order-media-assets-target='availableSelect']")
    if (!select) return

    select.querySelectorAll("option").forEach((option) => {
      if (!option.value) return

      const kind = option.dataset.contentKind
      const ok = this.clipMatchesMedium(kind, medium)
      option.hidden = !ok
      option.disabled = !ok
    })
    if (select.selectedOptions[0]?.disabled) select.value = ""
  }

  refreshClipRemoveButtons() {
    const list = this.element.querySelector("[data-order-media-assets-target='list']")
    if (!list) return

    const rows = list.querySelectorAll("[data-order-media-assets-target='row']")
    const canRemove = rows.length > 1
    list.querySelectorAll("[data-order-media-assets-target='removeButton']").forEach((button) => {
      button.disabled = !canRemove
      button.classList.toggle("btn-disabled", !canRemove)
    })
  }
}
