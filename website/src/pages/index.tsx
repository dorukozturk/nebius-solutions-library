import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import Heading from '@theme/Heading';

import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={styles.heroBanner}>
      <div className="container">
        <div className={styles.heroCopy}>
          <p className={styles.eyebrow}>Nebius AI Cloud</p>
          <Heading as="h1" className={styles.heroTitle}>
            {siteConfig.title}
          </Heading>
          <p className={styles.heroSubtitle}>{siteConfig.tagline}</p>
          <div className={styles.buttons}>
            <Link className="button button--primary button--lg" to="/docs/intro">
              Browse docs
            </Link>
          </div>
        </div>
        <div className={styles.catalogGrid}>
          <article className={styles.catalogCard}>
            <p className={styles.catalogLabel}>Training</p>
            <Heading as="h2" className={styles.catalogTitle}>
              Soperator
            </Heading>
            <p className={styles.catalogText}>
              Slurm on Kubernetes on Nebius AI Cloud, documented from deployment
              through validation.
            </p>
            <Link className={styles.catalogLink} to="/docs/soperator/overview">
              Open Soperator docs
            </Link>
          </article>
          <article className={styles.catalogCard}>
            <p className={styles.catalogLabel}>Training</p>
            <Heading as="h2" className={styles.catalogTitle}>
              K8s Training
            </Heading>
            <p className={styles.catalogText}>
              Managed Kubernetes for training workloads with CPU and GPU node
              groups, shared storage, observability, and optional Ray add-ons.
            </p>
            <Link className={styles.catalogLink} to="/docs/k8s-training/overview">
              Open K8s Training docs
            </Link>
          </article>
        </div>
      </div>
    </header>
  );
}

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.title}
      description="Nebius Solutions Library documentation for Soperator, Kubernetes training, and future reference architectures.">
      <HomepageHeader />
      <main>
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
