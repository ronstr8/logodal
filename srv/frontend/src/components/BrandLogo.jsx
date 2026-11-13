import { BRAND } from '../brand';
import LogodalLogo from './LogodalLogo';

// Logo for the active brand. Brands without their own logo fall back to Logodal's.
const LOGOS = {
    logodal: LogodalLogo,
};

const BrandLogo = (props) => {
    const Logo = LOGOS[BRAND] || LogodalLogo;
    return <Logo {...props} />;
};

export default BrandLogo;
