// ESLint for the LuCI app's JavaScript (packages/luci-app-letkite/htdocs).
// LuCI loads each file as the body of a function: 'require' directives at
// the top, a `return` of the view or class at the end, and these globals.
import globals from "globals";

export default [
  {
    files: ["packages/luci-app-letkite/htdocs/**/*.js"],
    ignores: ["packages/luci-app-letkite/htdocs/luci-static/resources/letkite/qrcode.js"],
    languageOptions: {
      ecmaVersion: 2017,
      sourceType: "script",
      parserOptions: { ecmaFeatures: { globalReturn: true } },
      globals: {
        ...globals.browser,
        L: "readonly",
        E: "readonly",
        _: "readonly",
        N_: "readonly",
        // the 'require x' directives bind these
        view: "readonly",
        rpc: "readonly",
        ui: "readonly",
        poll: "readonly",
        dom: "readonly",
        form: "readonly",
        uci: "readonly",
        fs: "readonly",
        baseclass: "readonly",
        qrcode: "readonly",
      },
    },
    rules: {
      "no-undef": "error",
      "no-unused-vars": ["error", { args: "none" }],
      "no-redeclare": "error",
      "no-unreachable": "error",
      "no-eval": "error",
      "no-implied-eval": "error",
      "no-new-func": "error",
      "no-script-url": "error",
      "eqeqeq": ["error", "smart"],
      "no-var": "off",
    },
  },
  {
    // the vendored QR library: only that it parses
    files: ["packages/luci-app-letkite/htdocs/luci-static/resources/letkite/qrcode.js"],
    languageOptions: {
      ecmaVersion: 5,
      sourceType: "script",
      parserOptions: { ecmaFeatures: { globalReturn: true } },
    },
    rules: {},
  },
];
