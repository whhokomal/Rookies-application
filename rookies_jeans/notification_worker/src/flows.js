// Every automatic notification: when it goes out and what it says.
//
// Change timings or wording here and redeploy (`npm run deploy`); the app
// doesn't need an update. Each flow is a list of steps; `after` is counted
// from the moment the flow starts (e.g. from the last cart change).
//
// Flow options:
//   quiet         waits for the morning if due during quiet hours
//   capped        counts toward MAX_PROMOS_PER_DAY and waits a day when over it
//   stopIfOrdered dropped when the customer orders after the flow started
//   needsCart     dropped when the saved cart is empty or already checked out
//
// msg(c) gets: c.name (first name or ''), c.coupon (*_COUPON settings), and
// whatever the flow was started with (product title/handle, order name ...).

export const MIN = 60 * 1000;
export const HOUR = 60 * MIN;
export const DAY = 24 * HOUR;

const hi = (c) => (c.name ? `${c.name}, ` : '');
const productLink = (c) => (c.handle ? `/products/${c.handle}` : '/home');

export const FLOWS = {
  // New install. Stops once they order.
  welcome: {
    quiet: true, capped: true, stopIfOrdered: true,
    steps: [
      {
        after: 10 * MIN,
        msg: (c) => ({
          title: 'Welcome to Rookies 👖',
          body: c.welcomeCoupon
            ? `Use code ${c.welcomeCoupon} for extra off on your first order.`
            : 'New fits drop every week. Have a look around.',
          link: '/home',
        }),
      },
      {
        after: 2 * DAY,
        msg: () => ({
          title: 'Trending right now 🔥',
          body: 'See what everyone is adding to cart this week.',
          link: '/collections/trending-now',
        }),
      },
      {
        after: 6 * DAY,
        msg: (c) => ({
          title: c.welcomeCoupon ? 'Your first-order code ends tomorrow' : 'Still looking for the perfect fit?',
          body: c.welcomeCoupon
            ? `${hi(c)}${c.welcomeCoupon} is valid till tomorrow. Don't miss it.`
            : 'Hot deals on jeans and shirts are live now.',
          link: '/collections/hot-deals',
        }),
      },
    ],
  },

  // Items in cart, no checkout. Restarts on every cart change.
  cart: {
    quiet: true, capped: true, stopIfOrdered: true, needsCart: true,
    steps: [
      {
        after: 1 * HOUR,
        msg: (c) => ({
          title: `${hi(c)}you left something behind 👀`,
          body: c.count > 1
            ? `${c.itemTitle} and ${c.count - 1} more are still in your cart.`
            : `${c.itemTitle || 'Your pick'} is still in your cart.`,
          link: '/cart',
        }),
      },
      {
        after: 12 * HOUR,
        msg: (c) => ({
          title: 'Your cart is getting lonely',
          body: 'Sizes are selling out fast. Grab yours before someone else does.',
          link: '/cart',
        }),
      },
      {
        after: 24 * HOUR,
        msg: (c) => ({
          title: c.cartCoupon ? 'A little something to help you decide 🎁' : 'Last call on your cart',
          body: c.cartCoupon
            ? `Use code ${c.cartCoupon} and check out your cart today.`
            : `${c.itemTitle || 'Your cart items'} won't be held much longer.`,
          link: '/cart',
        }),
      },
    ],
  },

  // Opened checkout but no order came through (payment failed or backed out).
  checkout: {
    quiet: true, capped: false, stopIfOrdered: true,
    steps: [
      {
        after: 20 * MIN,
        msg: () => ({
          title: 'Your order is not placed yet',
          body: 'Looks like checkout didn\'t finish. Your items are saved, retry in one tap.',
          link: '/cart',
        }),
      },
      {
        after: 6 * HOUR,
        msg: (c) => ({
          title: `${hi(c)}still want these?`,
          body: 'Complete your order now. COD available.',
          link: '/cart',
        }),
      },
    ],
  },

  // Opened a product, didn't add it. One per day at most (see index.js).
  browse: {
    quiet: true, capped: true, stopIfOrdered: false,
    steps: [
      {
        after: 3 * HOUR,
        msg: (c) => ({
          title: 'Still thinking about it?',
          body: `${c.title || 'The style you checked out'} is still available in your size.`,
          link: productLink(c),
          image: c.image,
        }),
      },
    ],
  },

  restock: {
    quiet: true, capped: true,
    steps: [{
      after: 0,
      msg: (c) => ({
        title: 'Back in stock 🙌',
        body: `${c.title || 'An item on your wishlist'} is back. Grab your size before it's gone again.`,
        link: productLink(c),
        image: c.image,
      }),
    }],
  },

  price_drop: {
    quiet: true, capped: true,
    steps: [{
      after: 0,
      msg: (c) => ({
        title: 'Price drop on your wishlist 📉',
        body: `${c.title || 'An item you saved'} is now ₹${c.price}.`,
        link: productLink(c),
        image: c.image,
      }),
    }],
  },

  // Order updates: always sent right away, day or night.
  order_confirmed: {
    steps: [{
      after: 0,
      msg: (c) => ({
        title: 'Order confirmed ✅',
        body: `${hi(c)}we got your order${c.orderName ? ` ${c.orderName}` : ''}. We'll tell you when it ships.`,
        link: '/orders',
      }),
    }],
  },
  shipped: {
    steps: [{
      after: 0,
      msg: (c) => ({
        title: 'Your order has shipped 📦',
        body: `${c.orderName ? `Order ${c.orderName}` : 'Your order'} is on its way.`,
        link: '/orders',
      }),
    }],
  },
  out_for_delivery: {
    steps: [{
      after: 0,
      msg: () => ({
        title: 'Out for delivery today 🚚',
        body: 'Keep your phone handy, your Rookies order arrives today.',
        link: '/orders',
      }),
    }],
  },
  delivered: {
    steps: [{
      after: 0,
      msg: () => ({
        title: 'Delivered!',
        body: 'Your order has been delivered. Enjoy the new fit.',
        link: '/orders',
      }),
    }],
  },

  // Started when an order is delivered.
  review: {
    quiet: true, capped: false,
    steps: [{
      after: 3 * DAY,
      msg: (c) => ({
        title: 'How\'s the fit?',
        body: `${hi(c)}tell us what you think of your order. It helps others pick the right size.`,
        link: '/orders',
      }),
    }],
  },

  // Started by every order; a newer order starts it again.
  repeat: {
    quiet: true, capped: true, stopIfOrdered: true,
    steps: [
      {
        after: 10 * DAY,
        msg: (c) => ({
          title: `${hi(c)}new arrivals picked for you`,
          body: 'Fresh styles that go great with your last order.',
          link: '/collections/trending-now',
        }),
      },
      {
        after: 30 * DAY,
        msg: () => ({
          title: 'It\'s been a while 👋',
          body: 'A lot has dropped since your last order. Come see.',
          link: '/home',
        }),
      },
      {
        after: 60 * DAY,
        msg: (c) => ({
          title: 'We miss you',
          body: c.winbackCoupon
            ? `Here's ${c.winbackCoupon} for extra off on your next order.`
            : 'Hot deals are live. Your next favourite pair is waiting.',
          link: '/collections/hot-deals',
        }),
      },
    ],
  },

  // Sent from POST /admin/broadcast; the text comes with the request.
  campaign: {
    quiet: true, capped: false,
    steps: [{
      after: 0,
      msg: (c) => ({
        title: fill(c.title, c),
        body: fill(c.body, c),
        link: c.link || '/home',
        image: c.image,
      }),
    }],
  },
};

// "{name}" in broadcast text becomes the first name (or "there").
function fill(text, c) {
  return String(text || '').replace(/\{name\}/g, c.name || 'there');
}

export function flowDef(flow) {
  return FLOWS[flow.split(':')[0]];
}
