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
      row.querySelectorAll("input, select").forEach((field) => { field.value = "" })
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

    const start = Math.min(...bounds.map(([from]) => from))
    const end = Math.max(...bounds.map(([, to]) => to))
    this.setWindow(row, start < end ? this.clock(start) : "", start < end ? this.clock(end) : "")
  }

  syncFromParts(event) {
    const row = event.target.closest("[data-order-windows-target='row']")
    const which = event.target.dataset.orderWindowsPart?.split("-")[0]
    if (!row || (which !== "start" && which !== "end")) return

    this.markManual(event)
    this.writeHiddenClock(row, which)
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
    this.applyClock(row, "start", startsAt)
    this.applyClock(row, "end", endsAt)
    this.requestRecompute()
  }

  applyClock(row, which, value) {
    const hidden = this.hiddenClock(row, which)
    if (hidden) hidden.value = value

    const [hour = "", minute = ""] = String(value || "").split(":")
    const hourSelect = row.querySelector(`[data-order-windows-part='${which}-hour']`)
    const minuteSelect = row.querySelector(`[data-order-windows-part='${which}-minute']`)
    if (hourSelect) hourSelect.value = hour
    if (minuteSelect) minuteSelect.value = minute
  }

  writeHiddenClock(row, which) {
    const hidden = this.hiddenClock(row, which)
    if (!hidden) return

    const hour = row.querySelector(`[data-order-windows-part='${which}-hour']`)?.value ?? ""
    const minute = row.querySelector(`[data-order-windows-part='${which}-minute']`)?.value ?? ""
    const hours = Number.parseInt(hour, 10)
    const minutes = Number.parseInt(minute, 10)
    if (hour === "" || minute === "" || hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      hidden.value = ""
      return
    }

    hidden.value = this.clock(hours * 60 + minutes)
  }

  hiddenClock(row, which) {
    const target = which === "start" ? "startsAt" : "endsAt"
    return row.querySelector(`[data-order-windows-target='${target}']`)
  }

  clock(minutes) {
    const total = minutes >= 24 * 60 ? (23 * 60) + 59 : minutes
    const hours = Math.floor(total / 60)
    const remainder = total % 60
    return `${String(hours).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`
  }

  requestRecompute() {
    this.dispatch("recompute", { prefix: "order-grid" })
  }
}
