import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Nebius Solutions Library',
  tagline: 'Reference architectures, deployment guides, and operations docs for Nebius AI Cloud.',
  favicon: 'img/favicon.ico',

  future: {
    v4: true,
  },

  url: 'https://nebius.github.io',
  baseUrl: '/',
  organizationName: 'nebius',
  projectName: 'nebius-solutions-library',

  onBrokenLinks: 'throw',
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl:
            'https://github.com/nebius/nebius-solutions-library/tree/main/website/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/docusaurus-social-card.jpg',
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Nebius Solutions Library',
      logo: {
        alt: 'Nebius logo',
        src: 'img/nebius-light.png',
        srcDark: 'img/nebius-dark.png',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
          href: 'https://github.com/nebius/nebius-solutions-library',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Overview',
              to: '/docs/intro',
            },
            {
              label: 'Training',
              to: '/docs/soperator/overview',
            },
          ],
        },
        {
          title: 'Solutions',
          items: [
            {
              label: 'K8s Training',
              to: '/docs/k8s-training/overview',
            },
            {
              label: 'SLURM on K8s',
              to: '/docs/soperator/overview',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'Repository',
              href: 'https://github.com/nebius/nebius-solutions-library',
            },
            {
              label: 'Nebius Docs',
              href: 'https://docs.nebius.com/',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Nebius. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.oneDark,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
