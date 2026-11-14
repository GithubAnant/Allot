# Third-party notices

This project is independent of the AI providers shown in its interface. Names and logos identify integrations; they do not imply endorsement.

| Component | Source | License |
| --- | --- | --- |
| T3 Code usage logic and UI reference | [pingdotgg/t3code](https://github.com/pingdotgg/t3code), revision `60f70d98cdeb2c692db649b9ade3adf74dd62bf9` | [MIT, T3 Tools Inc.](docs/T3-LICENSE.txt) |
| Geist font | [vercel/geist-font](https://github.com/vercel/geist-font) | [SIL Open Font License 1.1](docs/GEIST-LICENSE.txt) |
| Provider logo assets | [lobehub/lobe-icons](https://github.com/lobehub/lobe-icons) | [MIT, LobeHub](docs/PROVIDER-ICONS-LICENSE.txt) |
| LiteLLM offline model-price snapshot | [BerriAI/litellm](https://github.com/BerriAI/litellm), [pinned source](docs/MODEL-RATES-SOURCE.json) | [MIT](docs/LITELLM-LICENSE.txt) |
| esbuild (development only) | [evanw/esbuild](https://github.com/evanw/esbuild) | MIT, Evan Wallace |

Original T3 source copies, adapted modules and a source hash manifest are in `tools/t3-source/`. Native Swift filesystem/network code and SwiftUI views replace the upstream host and web UI. The graph is omitted. The application uses macOS JavaScriptCore to execute the bundled pure usage logic; Node and esbuild are only used when regenerating that bundle.
