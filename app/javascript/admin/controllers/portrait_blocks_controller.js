import { Controller } from "@hotwired/stimulus"

const FIELD_VISIBILITY = {
  commercial: { rotation: false, pick: false, time: false },
  filler: { rotation: true, pick: true, time: false },
  insertion: { rotation: true, pick: true, time: true },
  service_header_start: { rotation: true, pick: false, time: false },
  service_header_end: { rotation: true, pick: false, time: false }
}

export default class extends Controller {
  static targets = ["template", "list", "row"]

  connect() {
    this.toggleAll()
    this.refreshPositions()
  }

  disconnect() {
    document.querySelectorAll("[data-portrait-blocks-clone]").forEach((node) => node.remove())
  }

  add(event) {
    event.preventDefault()
    const fragment = this.templateTarget.content.cloneNode(true)
    this.listTarget.appendChild(fragment)
    this.refreshPositions()
    this.toggleAll()
  }

  remove(event) {
    event.preventDefault()
    this.rowFrom(event)?.remove()
    this.refreshPositions()
  }

  moveUp(event) {
    event.preventDefault()
    const row = this.rowFrom(event)
    const previous = row?.previousElementSibling
    if (row && previous) {
      row.parentNode.insertBefore(row, previous)
      this.refreshPositions()
    }
  }

  moveDown(event) {
    event.preventDefault()
    const row = this.rowFrom(event)
    const next = row?.nextElementSibling
    if (row && next) {
      row.parentNode.insertBefore(next, row)
      this.refreshPositions()
    }
  }

  kindChanged(event) {
    this.toggleRow(this.rowFrom(event))
  }

  rowFrom(event) {
    return event.currentTarget.closest("[data-portrait-blocks-target='row']")
  }

  refreshPositions() {
    this.rowTargets.forEach((row, index) => {
      const input = row.querySelector("[data-portrait-blocks-position]")
      if (input) input.value = index + 1
    })
  }

  toggleAll() {
    this.rowTargets.forEach((row) => this.toggleRow(row))
  }

  toggleRow(row) {
    if (!row) return

    const kind = row.querySelector("[data-portrait-blocks-kind]")?.value
    const visibility = FIELD_VISIBILITY[kind] || FIELD_VISIBILITY.commercial

    this.toggleField(row, "rotation", visibility.rotation)
    this.toggleField(row, "pick", visibility.pick)
    this.toggleField(row, "time", visibility.time)
  }

  toggleField(row, name, visible) {
    const wrapper = row.querySelector(`[data-portrait-blocks-field="${name}"]`)
    if (!wrapper) return

    wrapper.hidden = !visible
    wrapper.querySelectorAll("input, select").forEach((input) => {
      input.disabled = !visible
      if (!visible) input.value = ""
    })
  }
}
