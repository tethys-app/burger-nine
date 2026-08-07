Checkout flow redesign — white-label native iOS restaurant app

We need to refactor the checkout flow into a separate file/module and redesign it as a two-step checkout experience for a native iOS white-label restaurant delivery app.

The main issue today is that users often forget to switch between delivery and pickup / eat-in before opening the cart. To avoid mistakes, the selected order mode should be made explicit as soon as the user taps “Voir le panier”, and the checkout CTA should clearly remind the user of the current mode.

Step 1 — Order mode and address / pickup confirmation

When the user taps “Voir le panier”, show a modal sheet that takes a little more than half the screen height.

This first step lets the user confirm how they want to receive the order.

UI

The sheet should include:

* A segmented control:
    * Livraison
    * Sur place / à emporter
* An address selection area:
    * If the user already has a saved address, display it as a recap row.
    * Otherwise, display an address autocomplete field.
* A primary CTA that adapts to the selected mode:
    * For delivery: “Livrer à cette adresse”
    * For pickup / eat-in: “Je viendrai récupérer ma commande” or “Valider le retrait”

Changing the order mode should update both the CTA text and the CTA color so the selected mode is visually obvious.

Address autocomplete

For delivery, use MapKit for address autocomplete.

The API key is available as `MAPKIT_API_KEY` in the environment (`.env.local`).

The user should not be able to continue to payment until the delivery address has been confirmed.

Step 2 — Full checkout and payment

Once the address or pickup mode is confirmed, the half-screen modal should animate into a full-screen checkout view.

The transition should feel continuous: the address recap row from step 1 should remain visible and visually morph into the address recap section in the full checkout screen.

UI

The full checkout screen should include:

1. Order recap
2. Address / pickup recap
3. Delivery or pickup time row
4. Payment method
5. Pay CTA

Order recap behavior

The order recap should be compact and standardized in height.

To avoid a very long checkout screen, only display a limited number of product rows by default, for example 1 to 3 rows maximum.

If the cart contains more items, show a row such as:

“+ X autres articles”

The fee lines must always remain visible, regardless of the number of products. This includes things like:

* Subtotal
* Delivery fee
* Service fee
* Discounts
* Total

There should also be an expand button allowing the user to view the full order details.

Address / pickup recap

The address recap section should display the confirmed delivery address, or the selected pickup / eat-in mode.

This section must include an edit/change action.

When the user taps change, the checkout should return to step 1 so they can update the delivery mode or address.

Delivery / pickup time

Add a row showing the expected delivery or pickup time.

Examples:

* Livraison estimée : 25–35 min
* Prêt à récupérer : 15–20 min

Payment method

Use Stripe-style payment rows.

Apple Pay should be selected by default when available.

The payment section should include:

* Apple Pay — default selected
* Carte bancaire

The selected payment method should be visually clear.

Final CTA

The final CTA should clearly communicate the action and selected mode.

Examples:

* “Payer et commander en livraison”
* “Payer et commander à emporter”
* “Payer avec Apple Pay” if Apple Pay is selected and appropriate

The goal is to make the delivery mode impossible to miss, reduce user mistakes, and create a checkout flow that feels native, compact, and polished on iOS.
