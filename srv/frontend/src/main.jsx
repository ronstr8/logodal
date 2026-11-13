import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
import { BRAND, applyBrand } from './brand'
import './theme.css'
import './index.css'
import './i18n'

import { Suspense } from 'react'

applyBrand(BRAND)

ReactDOM.createRoot(document.getElementById('root')).render(
    <React.StrictMode>
        <Suspense fallback={<div className="loading-modal">Loading translations...</div>}>
            <App />
        </Suspense>
    </React.StrictMode>,
)
