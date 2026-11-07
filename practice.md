# Practice: תרגול בניית הדשבורד

תרגיל 4 - בניית דשבורד עם Claude Code לפי `spec.md`.

## שלבים
1. קריאת `spec.md` והבנת הדרישות.
2. יצירת נתוני דוגמה (CSV) - `generate-data.ps1`.
3. בניית `dashboard.template.html` (גרפים, מסננים, תחזית).
4. הוספת שעון וגרף עוגה (בקשה נוספת באמצע העבודה).
5. הרצה ובדיקה בדפדפן.

## פרומפט מקורי
> create dashboard for kupat holim meuhedet that include the blood laboratory and give an option to see the status in the year and per month and manage the future; create csv file that include all the workers and all the laboratories in the country

תוספת: "the dashboard need to include a clock and pie".

## איך מריצים
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File dashboard-output\generate-data.ps1
```
ואז פותחים את `dashboard-output\dashboard.html` בדפדפן.

## לקחים
- אין Python/Node במחשב - נעשה שימוש ב-PowerShell.
- PowerShell 5.1 מקלקל עברית בתוך קובץ `.ps1` ללא BOM, לכן טקסט עברי נשמר בקבצי `seed/` ונקרא ב-UTF-8.
- נתוני דוגמה חייבים להיות מסומנים כסינתטיים.

## שאלות לתרגול
- איך מחליפים את הנתונים הסינתטיים בייצוא אמיתי?
- איך משפרים את התחזית (עונתיות, רגרסיה)?
