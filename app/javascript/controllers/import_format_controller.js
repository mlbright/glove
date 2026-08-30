import { Controller } from "@hotwired/stimulus"

// Shows the import format that the selected account already dictates, and
// narrows the format reference down to the one bank that applies.
//
// Purely presentational: the server derives the format from the account and
// never reads one from the request, so without JS the import still works --
// the format line simply stays on its placeholder.
export default class extends Controller {
  static targets = ["account", "label", "entry", "referenceHeading"]

  connect() {
    this.accountChanged()
  }

  accountChanged() {
    const option = this.accountTarget.selectedOptions[0]
    const key = option ? option.dataset.format : ""
    const label = option ? option.dataset.formatLabel : ""

    this.renderLabel(label)
    this.renderReference(key)
  }

  renderLabel(label) {
    if (label) {
      this.labelTarget.textContent = label
    } else {
      this.labelTarget.innerHTML =
        '<span class="text-slate-500">Select an account to see its import format.</span>'
    }
  }

  // With no account chosen, every format stays visible as general reference.
  renderReference(key) {
    this.entryTargets.forEach((entry) => {
      entry.hidden = key ? entry.dataset.formatKey !== key : false
    })

    if (this.hasReferenceHeadingTarget) {
      this.referenceHeadingTarget.textContent = key
        ? "Expected CSV format"
        : "Supported formats"
    }
  }
}
