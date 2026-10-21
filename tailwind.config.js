/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        parchment: '#F3EFE5',
        paper: '#FCFAF5',
        ink: '#292B24',
        olive: '#596047',
        sage: '#AAB09B',
        line: '#DDD7CA',
        muted: '#716F66'
      },
      fontFamily: {
        display: ['Newsreader', 'Georgia', 'serif'],
        sans: ['Instrument Sans', 'ui-sans-serif', 'system-ui']
      },
      boxShadow: {
        quiet: '0 16px 50px rgba(52, 48, 37, 0.08)'
      }
    }
  },
  plugins: []
}
