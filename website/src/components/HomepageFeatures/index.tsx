import type {ReactNode} from 'react';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  kicker: string;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    kicker: 'Deploy',
    title: 'Infrastructure recipes backed by the repo',
    description: (
      <>
        Documentation is derived from the Terraform modules, example
        installations, and operational scripts already shipped in this library.
      </>
    ),
  },
  {
    kicker: 'Operate',
    title: 'Day-2 guidance, not only setup steps',
    description: (
      <>
        Cluster access, validation, testing, storage considerations, and common
        operational flows are treated as first-class documentation topics.
      </>
    ),
  },
  {
    kicker: 'Expand',
    title: 'Built to grow beyond Soperator',
    description: (
      <>
        The information architecture leaves room for `k8s-training` and future
        solutions without turning the docs into a single monolithic README.
      </>
    ),
  },
];

function Feature({kicker, title, description}: FeatureItem) {
  return (
    <article className={styles.featureCard}>
      <p className={styles.kicker}>{kicker}</p>
      <Heading as="h3" className={styles.title}>
        {title}
      </Heading>
      <p className={styles.description}>{description}</p>
    </article>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className={styles.header}>
          <p className={styles.sectionLabel}>Documentation direction</p>
          <Heading as="h2" className={styles.sectionTitle}>
            Start with deep coverage where the repo already has strong assets
          </Heading>
          <p className={styles.sectionText}>
            The first slice focuses on `soperator`, with structure ready for
            Kubernetes training and additional Nebius solutions.
          </p>
        </div>
        <div className={styles.grid}>
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
