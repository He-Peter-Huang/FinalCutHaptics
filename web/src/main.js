import { createApp } from 'vue'
import { createI18n } from 'vue-i18n'
import App from './App.vue'
import { messages } from './i18n.js'
import './style.css'

const saved = localStorage.getItem('lang')
const browserZh = (navigator.language || '').toLowerCase().startsWith('zh')
const i18n = createI18n({
  legacy: false,
  locale: saved || (browserZh ? 'zh' : 'en'),
  fallbackLocale: 'en',
  messages,
})

createApp(App).use(i18n).mount('#app')
