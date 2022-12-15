[![Netlify Status](https://api.netlify.com/api/v1/badges/985fa11c-afca-4fa7-ac9b-732f01bdc506/deploy-status)](https://app.netlify.com/sites/planter-docs/deploys)
[![Better Uptime Badge](https://betteruptime.com/status-badges/v1/monitor/k95y.svg)](https://betteruptime.com/?utm_source=status_badge)

# Documentation site for [Planter](https://planter.garden)

View live [documentation website](https://info.planter.garden)

## Stack
Built with Hugo, with the [Doks theme](https://getdoks.org/). Deployed on Netlify.

# Running locally

## Requirements

- [Git](https://git-scm.com/) — latest source release
- [Node.js](https://nodejs.org/) — latest LTS version or newer

<details>
<summary>Why Node.js?</summary>

Doks uses npm (included with Node.js) to centralize dependency management, making it [easy to update](https://getdoks.org/docs/help/how-to-update/) resources, build tooling, plugins, and build scripts.

</details>

## Get started

### 1. Download repository

```bash
git clone https://github.com/percula/planter_docs.git planter_docs && cd planter_docs
```

### 2. Install dependencies

```bash
npm install
```

### 3. Start development server

```bash
npm run start
```
