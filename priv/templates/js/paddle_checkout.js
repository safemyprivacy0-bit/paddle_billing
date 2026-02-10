// PaddleCheckout LiveView Hook
// Loads Paddle.js SDK and opens inline or overlay checkout
const PaddleCheckout = {
  mounted() {
    this.loadPaddleJs().then(() => {
      this.initPaddle()
    })
  },

  updated() {
    // Re-open checkout if transaction_id changed
    const txnId = this.el.dataset.transactionId
    if (txnId && txnId !== this.currentTxnId) {
      this.openCheckout(txnId)
    }
  },

  destroyed() {
    if (window.Paddle) {
      Paddle.Checkout.close()
    }
  },

  loadPaddleJs() {
    if (window.Paddle) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = "https://cdn.paddle.com/paddle/v2/paddle.js"
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
  },

  initPaddle() {
    const environment = this.el.dataset.environment
    const clientToken = this.el.dataset.clientToken

    if (environment === "sandbox") {
      Paddle.Environment.set("sandbox")
    }

    Paddle.Initialize({
      token: clientToken,
      eventCallback: (event) => this.handlePaddleEvent(event),
    })

    // Auto-open if transaction_id is already set
    const txnId = this.el.dataset.transactionId
    if (txnId) {
      this.openCheckout(txnId)
    }
  },

  openCheckout(transactionId) {
    this.currentTxnId = transactionId

    const settings = {
      displayMode: this.el.dataset.displayMode || "overlay",
      theme: this.el.dataset.theme || "light",
      locale: this.el.dataset.locale || "en",
    }

    // If displayMode is 'inline', set the target to the container element
    if (settings.displayMode === "inline") {
      const container =
        this.el.querySelector("[data-paddle-checkout-container]") || this.el
      settings.frameTarget =
        container.id || "paddle-checkout-container"
      settings.frameInitialHeight = parseInt(
        this.el.dataset.frameHeight || "450",
      )
      settings.frameStyle =
        this.el.dataset.frameStyle ||
        "width: 100%; background-color: transparent; border: none;"
    }

    Paddle.Checkout.open({
      transactionId: transactionId,
      settings: settings,
    })
  },

  handlePaddleEvent(event) {
    switch (event.name) {
      case "checkout.loaded":
        this.pushEvent("paddle-checkout-loaded", {})
        break
      case "checkout.completed":
        this.pushEvent("paddle-checkout-completed", {
          transaction_id: event.data?.transaction_id,
          status: event.data?.status,
        })
        break
      case "checkout.closed":
        this.pushEvent("paddle-checkout-closed", {})
        break
      case "checkout.error":
        this.pushEvent("paddle-checkout-error", {
          error: event.data?.error?.message || "Unknown error",
        })
        break
      case "checkout.customer.created":
        this.pushEvent("paddle-checkout-customer-created", {
          customer_id: event.data?.customer?.id,
          email: event.data?.customer?.email,
        })
        break
      case "checkout.payment.selected":
        this.pushEvent("paddle-checkout-payment-selected", {
          payment_method: event.data?.payment?.method_type,
        })
        break
    }
  },
}

export default PaddleCheckout
