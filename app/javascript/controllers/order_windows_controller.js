import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "row"]

  add(event) {
    event.preventDefault()
    if (!this.hasTemplateTarget || !this.hasListTarget) return

    this.listTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML)
    this.requestRecompute()
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-order-windows-target='row']")
    if (!row) return

    const rows = this.listTarget.querySelectorAll("[data-order-windows-target='row']")
    if (rows.length <= 1) {
      row.dataset.orderWindowsAutomatic = "false"
      row.querySelectorAll("input").forEach((input) => { input.value = "" })
      this.requestRecompute()
      return
    }

    row.remove()
    this.requestRecompute()
  }

  updateAutomaticWindow() {
    const row = this.listTarget.querySelector("[data-order-windows-automatic='true']")
    if (!row) return

    const selectedRows = Array.from(
      this.element.querySelectorAll("[data-order-screen-picker-target='row']")
    ).filter((pickerRow) => pickerRow.querySelector("input[type='checkbox']")?.checked)

    if (selectedRows.length === 0) {
      this.setWindow(row, "08:00", "23:00")
      return
    }

    const bounds = selectedRows.flatMap((pickerRow) => this.hoursBounds(pickerRow))
    if (bounds.length === 0) {
      this.setWindow(row, "", "")
      return
    }

    const start = Math.max(...bounds.map(([from]) => from))
    const end = Math.min(...bounds.map(([, to]) => to))
    this.setWindow(row, start < end ? this.clock(start) : "", start < end ? this.clock(end) : "")
  }

  markManual(event) {
    const row = event.target.closest("[data-order-windows-target='row']")
    if (row?.dataset.orderWindowsAutomatic === "true") {
      row.dataset.orderWindowsAutomatic = "false"
    }
  }

  hoursBounds(pickerRow) {
    let hoursByDate = {}
    try {
      hoursByDate = JSON.parse(pickerRow.dataset.hours || "{}")
    } catch (_error) {
      return []
    }

    const dailyBounds = Object.values(hoursByDate).map((hours) => {
      if (!Array.isArray(hours) || hours.length === 0) return null

      const numericHours = hours.map(Number).filter((hour) => hour >= 0 && hour <= 23)
      if (numericHours.length === 0) return null

      return [Math.min(...numericHours) * 60, (Math.max(...numericHours) + 1) * 60]
    })

    return dailyBounds.includes(null) ? [] : dailyBounds.filter(Boolean)
  }

  setWindow(row, startsAt, endsAt) {
    row.querySelector("[data-order-windows-target='startsAt']").value = startsAt
    row.querySelector("[data-order-windows-target='endsAt']").value = endsAt
    this.requestRecompute()
  }

  clock(minutes) {
    const hours = Math.floor(minutes / 60)
    const remainder = minutes % 60
    return `${String(hours).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`
  }

  requestRecompute() {
    this.dispatch("recompute", { prefix: "order-grid" })
  }
}
