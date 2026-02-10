return {
  {
    "atdma/caelestia-nvim",
    lazy = false,
    priority = 1000,
    config = function() require("caelestia").setup() end,
  },
}
