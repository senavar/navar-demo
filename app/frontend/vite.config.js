import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: {
    proxy: {
      // This will proxy any request starting with /api to your Flask backend
      '/api': {
        target: 'http://localhost:5001', // The address of your Flask server
        changeOrigin: true, // Recommended for virtual hosts
      }
    }
  }
})