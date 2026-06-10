// Visitor counter — calls the API on page load, increments + displays the count.
(function () {
  "use strict";

  // POST (not GET): the call mutates state (increments the counter), and POST
  // avoids browser/proxy caching and accidental triggers from prefetchers/bots.
  var COUNTER_API = "https://z8v6craitg.execute-api.ap-south-1.amazonaws.com/count";

  var el = document.getElementById("visit-count");

  fetch(COUNTER_API, { method: "POST" })
    .then(function (res) { return res.json(); })
    .then(function (data) {
      // data looks like { "views": 42 }
      if (el) el.textContent = Number(data.views).toLocaleString();
    })
    .catch(function () {
      // Network/API failure: leave a dash rather than a broken page.
      if (el) el.textContent = "—";
    });
})();
