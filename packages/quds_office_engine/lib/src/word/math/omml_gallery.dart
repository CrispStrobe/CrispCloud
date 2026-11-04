import 'omml_document.dart';
import 'omml_linear.dart';

/// Built-in Equation gallery matching the Word Insert → Equation list.
class OmmlGalleryItem {
  /// OmmlGalleryItem API.
  const OmmlGalleryItem({
    required this.id,
    required this.en,
    required this.ar,
    required this.linear,
  });

  /// id API.
  final String id;

  /// en API.
  final String en;

  /// ar API.
  final String ar;

  /// linear API.
  final String linear;

  /// build API.
  OmmlEquation build() => OmmlEquation(
    root: OmmlLinear.parse(linear),
    display: OmmlDisplay.display,
  );

  /// title API.
  String title({required bool arabic}) => arabic ? ar : en;
}

/// Class OmmlGallery.
abstract final class OmmlGallery {
  /// items API.
  static const List<OmmlGalleryItem> items = <OmmlGalleryItem>[
    OmmlGalleryItem(
      id: 'blank',
      en: 'Blank equation',
      ar: 'معادلة فارغة',
      linear: '',
    ),
    OmmlGalleryItem(
      id: 'pythagorean',
      en: 'Pythagorean theorem',
      ar: 'نظرية فيثاغورس',
      linear: 'a^2+b^2=c^2',
    ),
    OmmlGalleryItem(
      id: 'quadratic',
      en: 'Quadratic formula',
      ar: 'القانون التربيعي',
      linear: 'x=(-b±√(b^2-4ac))/(2a)',
    ),
    OmmlGalleryItem(
      id: 'circle-area',
      en: 'Area of a circle',
      ar: 'مساحة الدائرة',
      linear: 'A=πr^2',
    ),
    OmmlGalleryItem(
      id: 'trig-identity',
      en: 'Trigonometric identity',
      ar: 'متطابقة مثلثية',
      linear: 'sin^2 θ+cos^2 θ=1',
    ),
    OmmlGalleryItem(
      id: 'binomial',
      en: 'Binomial theorem',
      ar: 'نظرية ذات الحدين',
      linear: '(x+a)^n=∑_(k=0)^n x^k a^(n-k)',
    ),
    OmmlGalleryItem(
      id: 'sum-n',
      en: 'Sum of first n integers',
      ar: 'مجموع الأعداد',
      linear: '∑_(i=1)^n i=n(n+1)/2',
    ),
    OmmlGalleryItem(
      id: 'integral',
      en: 'Definite integral',
      ar: 'تكامل محدد',
      linear: '∫_a^b f(x) dx',
    ),
    OmmlGalleryItem(
      id: 'taylor',
      en: 'Taylor expansion',
      ar: 'متسلسلة تايلور',
      linear: 'e^x=1+x+x^2/2+x^3/6+⋯',
    ),
    OmmlGalleryItem(
      id: 'fourier',
      en: 'Fourier series',
      ar: 'متسلسلة فورييه',
      linear: 'f(x)=a_0+∑_(n=1)^∞ (a_n cos(nπx/L)+b_n sin(nπx/L))',
    ),
    OmmlGalleryItem(
      id: 'limit',
      en: 'Limit definition',
      ar: 'تعريف النهاية',
      linear: 'lim_(x→0) sin(x)/x=1',
    ),
    OmmlGalleryItem(
      id: 'einstein',
      en: 'Mass–energy',
      ar: 'الطاقة والكتلة',
      linear: 'E=mc^2',
    ),
  ];

  /// byId API.
  static OmmlGalleryItem byId(String id) {
    for (final OmmlGalleryItem item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return items.first;
  }
}
