export const CONFIG = {
    // Donation Settings
    PAYPAL_EMAIL: window.LOGODAL_CONFIG?.PAYPAL_EMAIL || import.meta.env.VITE_PAYPAL_EMAIL || 'quinnfazigu@gmail.com',

    // Feature Toggles
    KOFI_ID: window.LOGODAL_CONFIG?.KOFI_ID || import.meta.env.VITE_KOFI_ID || 'logodal',
    KOFI_ENABLED: window.LOGODAL_CONFIG?.KOFI_ENABLED !== undefined ? window.LOGODAL_CONFIG.KOFI_ENABLED : (import.meta.env.VITE_KOFI_ENABLED !== 'false'),
    PAYPAL_ENABLED: window.LOGODAL_CONFIG?.PAYPAL_ENABLED !== undefined ? window.LOGODAL_CONFIG.PAYPAL_ENABLED : (import.meta.env.VITE_PAYPAL_ENABLED !== 'false'),

    // Runtime Configuration
    LOG_LEVEL: window.LOGODAL_CONFIG?.LOG_LEVEL || import.meta.env.VITE_LOG_LEVEL || 'info',
    PROJECT_CODE_LINK: window.LOGODAL_CONFIG?.PROJECT_CODE_LINK || import.meta.env.VITE_PROJECT_CODE_LINK || 'https://github.com/ronstr8/logodal',
};

export default CONFIG;
