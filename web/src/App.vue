<script setup>
import { useI18n } from 'vue-i18n'
import { watch } from 'vue'

const { t, locale } = useI18n()

function setLang(l) {
  locale.value = l
  localStorage.setItem('lang', l)
  document.documentElement.lang = l === 'zh' ? 'zh-CN' : 'en'
}
watch(locale, (l) => (document.documentElement.lang = l === 'zh' ? 'zh-CN' : 'en'), { immediate: true })
</script>

<template>
  <div class="wrap">
    <nav>
      <div class="brand"><img src="/icon.png" alt="" /> FinalCutHaptics</div>
      <div class="nav-right">
        <a href="#why">{{ t('nav.features') }}</a>
        <a href="#start">{{ t('nav.start') }}</a>
        <a href="https://github.com/He-Peter-Huang/FinalCutHaptics" target="_blank" rel="noopener">GitHub</a>
        <div class="lang">
          <button :class="{ on: locale === 'en' }" @click="setLang('en')">EN</button>
          <span>/</span>
          <button :class="{ on: locale === 'zh' }" @click="setLang('zh')">中文</button>
        </div>
      </div>
    </nav>

    <header class="hero">
      <span class="badge">● {{ t('hero.badge') }}</span>
      <h1>{{ t('hero.title_pre') }}<span class="grad">{{ t('hero.title_em') }}</span>{{ t('hero.title_post') }}</h1>
      <p class="tag">{{ t('hero.tagline') }}</p>
      <div class="cta">
        <a class="btn btn-primary" href="https://github.com/He-Peter-Huang/FinalCutHaptics/releases/latest/download/FinalCutHaptics.pkg">↓ {{ t('hero.download') }}</a>
      </div>
      <p class="meta">{{ t('hero.meta') }}</p>
    </header>

    <section id="why">
      <h2>{{ t('why.heading') }}</h2>
      <div class="grid">
        <div class="card"><div class="ic">✦</div><h3>{{ t('why.a_t') }}</h3><p>{{ t('why.a_d') }}</p></div>
        <div class="card"><div class="ic">⟁</div><h3>{{ t('why.b_t') }}</h3><p>{{ t('why.b_d') }}</p></div>
        <div class="card"><div class="ic">❍</div><h3>{{ t('why.c_t') }}</h3><p>{{ t('why.c_d') }}</p></div>
      </div>
    </section>

    <section id="start">
      <h2>{{ t('start.heading') }}</h2>
      <div class="steps">
        <div class="step"><div><h3>{{ t('start.s1_t') }}</h3><p>{{ t('start.s1_d') }}</p></div></div>
        <div class="step"><div><h3>{{ t('start.s2_t') }}</h3><p>{{ t('start.s2_d') }}</p></div></div>
        <div class="step"><div><h3>{{ t('start.s3_t') }}</h3><p>{{ t('start.s3_d') }}</p></div></div>
      </div>
      <div class="note">🎚️ <span>{{ t('start.note') }}</span></div>
    </section>

    <section>
      <h2>{{ t('feat.heading') }}</h2>
      <div class="features">
        <div class="feat"><span class="dot"></span>{{ t('feat.f1') }}</div>
        <div class="feat"><span class="dot"></span>{{ t('feat.f2') }}</div>
        <div class="feat"><span class="dot"></span>{{ t('feat.f3') }}</div>
        <div class="feat"><span class="dot"></span>{{ t('feat.f4') }}</div>
        <div class="feat"><span class="dot"></span>{{ t('feat.f5') }}</div>
        <div class="feat"><span class="dot"></span>{{ t('feat.f6') }}</div>
      </div>
    </section>

    <footer>
      <div>{{ t('foot.by') }} · <a href="https://github.com/He-Peter-Huang/FinalCutHaptics" target="_blank" rel="noopener">Open source on GitHub</a></div>
      <div class="disc">{{ t('foot.disclaimer') }}</div>
    </footer>
  </div>
</template>
