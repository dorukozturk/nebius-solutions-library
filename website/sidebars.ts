import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    'intro',
    {
      type: 'category',
      label: 'Solutions',
      items: [
        {
          type: 'category',
          label: 'Training',
          items: [
            {
              type: 'category',
              label: 'Soperator',
              items: [
                'soperator/overview',
                'soperator/architecture',
                'soperator/generated-configuration-reference',
                'soperator/prerequisites-and-installation',
                'soperator/access-and-day-2-operations',
                'soperator/testing-and-validation',
              ],
            },
            {
              type: 'category',
              label: 'K8s Training',
              items: [
                'k8s-training/overview',
                'k8s-training/architecture',
                'k8s-training/configuration-reference',
                'k8s-training/generated-configuration-reference',
                'k8s-training/prerequisites-and-deployment',
                'k8s-training/access-storage-and-operations',
              ],
            },
          ],
        },
        {
          type: 'category',
          label: 'Network',
          items: [
            {
              type: 'category',
              label: 'Bastion',
              items: [
                'bastion/overview',
                'bastion/generated-configuration-reference',
              ],
            },
            {
              type: 'category',
              label: 'WireGuard',
              items: [
                'wireguard/overview',
                'wireguard/generated-configuration-reference',
              ],
            },
          ],
        },
        {
          type: 'category',
          label: 'Compute',
          items: [
            {
              type: 'category',
              label: 'DSVM',
              items: [
                'dsvm/overview',
                'dsvm/generated-configuration-reference',
              ],
            },
            {
              type: 'category',
              label: 'NFS Server',
              items: [
                'nfs-server/overview',
                'nfs-server/generated-configuration-reference',
              ],
            },
            {
              type: 'category',
              label: 'VM Instance',
              items: [
                'vm-instance/overview',
                'vm-instance/generated-configuration-reference',
              ],
            },
            {
              type: 'category',
              label: 'Compute Testing',
              items: [
                'compute-testing/overview',
                'compute-testing/generated-configuration-reference',
              ],
            },
          ],
        },
      ],
    },
  ],
};

export default sidebars;
