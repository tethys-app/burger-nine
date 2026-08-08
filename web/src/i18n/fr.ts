// Centralized copy for the marketing/landing pages (Nav, Top, Bottom, home,
// /carte picker). Keeping every string here means a translation just means
// swapping this file — no hunting through .astro markup for hardcoded text.
export const fr = {
  nav: {
    carte: 'La carte',
    hits: 'Les hits',
    spot: 'Le spot',
    restos: 'Nos restos',
    franchise: 'Franchise',
    carrieres: 'Carrières',
    commandes: 'Mes commandes',
    commander: 'Commander',
    openMenuAria: 'Ouvrir le menu',
    homeAria: 'Burger Nine — accueil',
  },
  hero: {
    headlineLead: 'Viens tester',
    headlineMid: 'la ',
    headlineHighlight: 'frappe',
    headlineTrail: 'du Nine',
    headlineLines: ["C'est testé.", "C'est validé."],
    cta: 'Commander',
    micro: "Envie d'ouvrir un Burger Nine ?",
    cityAlt: "Skyline néon la nuit avec l'enseigne Burger Nine et le panneau « C'est d'la frappe »",
  },
  carte: {
    overline: '01 · La carte',
    title: 'En vedette',
    catalogueLink: 'Voir le catalogue complet',
    items: {
      burgers: { name: 'Burgers', alt: 'Burger smashé Burger Nine' },
      tacos: { name: 'Tacos', alt: "French tacos Burger Nine devant l'enseigne néon" },
      rizCrousty: { name: 'Riz Crousty', alt: 'Riz Crousty — riz et poulet croustillant sauce' },
      bowls: { name: 'Bowls', alt: 'Bowl bœuf smashé pickles cheddar' },
    },
  },
  hits: {
    overline: '02 · Les hits',
    title: ['Commandez.', 'Recommandez.'],
    side: 'Des burgers gourmands, sandwichs bien garnis, tacos gratinés & plus encore. Oui, ça frappe toujours autant.',
    discover: 'Découvrir',
    items: {
      smashBowl: { alt: 'Le Smash Bowl signature' },
      brochettes: { alt: 'Brochettes glazées BBQ' },
      tandoorSub: { alt: 'Le Tandoor Sub' },
    },
  },
  spot: {
    overline: '03 · Le spot',
    quote: "« Askip c'est la meilleure frappe du coin »",
    title: ['Le festin peut', 'commencer'],
    franchiseCta: 'Ouvrir mon Burger Nine',
    images: {
      salle: { alt: 'Burger Nine servi en salle' },
      bowlNeon: { alt: 'Bowl Burger Nine devant le néon' },
      plateaux: { alt: 'Plateaux à partager chez Burger Nine' },
    },
  },
  restos: {
    overline: '04 · Nos restaurants',
    title: ['Le Nine frappe à ta porte', 'Trouve ton Nine'],
  },
  footer: {
    tagline: "C'est vraiment de la frappe",
    nav: {
      carte: 'La carte',
      hits: 'Les hits',
      spot: 'Le spot',
      restos: 'Nos restos',
      franchise: 'Franchise',
      carrieres: 'Carrières',
      commander: 'Commander',
    },
    footerAria: 'Pied de page',
    socials: {
      instagram: { handle: '@b9.burgernine', label: 'Instagram' },
      tiktok: { handle: '@b9off', label: 'TikTok' },
      facebook: { handle: 'Burger9Officiel', label: 'Facebook' },
    },
    legal: {
      mentions: 'Mentions légales',
      cgv: 'CGV',
      confidentialite: 'Politique de confidentialité',
    },
    copyright: '© 2026 Burger Nine — bnine.fr · Tous droits réservés',
  },
  cartePicker: {
    metaTitle: 'La carte — Burger Nine',
    metaDescription:
      'Toute la carte Burger Nine, resto par resto : burgers, tacos, bowls, box, tex-mex, desserts et boissons, avec les vrais prix.',
    overline: 'La carte',
    h1: ['Choisis ton Nine,', "on t'affiche sa carte."],
    lede: "Le menu n'est pas identique partout — vois direct celui de ton resto.",
    cardCta: 'Voir la carte',
  },
  brand: {
    homeTitleSuffix: "C'est vraiment de la frappe",
  },
}

export type Fr = typeof fr
