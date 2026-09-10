import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "picker"]

  connect() {
    this.syncFromDisplay()
  }

  syncFromDisplay() {
    if (!this.hasDisplayTarget || !this.hasPickerTarget) return

    const iso = this.isoFromDisplay(this.displayTarget.value)
    if (iso) this.pickerTarget.value = iso
  }

  syncFromPicker() {
    if (!this.hasDisplayTarget || !this.hasPickerTarget) return

    const iso = this.pickerTarget.value
    if (!iso) return

    const [year, month, day] = iso.split("-")
    this.displayTarget.value = [day, month, year].join(".")
  }

  isoFromDisplay(value) {
    const trimmed = String(value || "").trim()
    const dotted = trimmed.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/)
    if (dotted) {
      const day = dotted[1].padStart(2, "0")
      const month = dotted[2].padStart(2, "0")
      const year = dotted[3]
      return this.validIso(year, month, day)
    }

    const iso = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})$/)
    if (iso) return this.validIso(iso[1], iso[2], iso[3])

    return ""
  }

  validIso(year, month, day) {
    const y = Number(year)
    const m = Number(month)
    const d = Number(day)
    const date = new Date(Date.UTC(y, m - 1, d))
    if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) return ""

    return `${year}-${month}-${day}`
  }
}
