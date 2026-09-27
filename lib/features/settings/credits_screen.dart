import 'package:flutter/material.dart';

import '../../ui/links.dart';

/// Settings -> Credits and licences: the attribution each data source requires, worded as its terms ask.
/// Hard-coded rather than read from the listings file, so it shows even when the listings haven't loaded.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(String title, List<String> lines, {String? url, Widget? leading}) => ListTile(
      leading: leading,
      title: Text(title),
      subtitle: Text(lines.join('\n')),
      trailing: url == null ? null : const Icon(Icons.open_in_new, size: 18),
      onTap: url == null ? null : () => openUrl(context, url),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Credits and licences')),
      body: ListView(
        children: [
          item(
            'Film details and posters',
            [
              'This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.',
            ],
            url: 'https://www.themoviedb.org',
            leading: Image.asset('assets/tmdb_logo.png', width: 40),
          ),
          item('Screenings and cinemas', [
            'Screening data from Clusterflick (CC BY 4.0), modified',
          ], url: 'https://clusterflick.com'),
          item('Licence for screening data', [
            'Creative Commons Attribution 4.0',
          ], url: 'https://creativecommons.org/licenses/by/4.0/'),
          item('Journeys', [
            'Powered by TfL Open Data',
            'Contains OS data © Crown copyright and database rights 2016',
            'Geomni UK Map data © and database rights [2019]',
          ], url: 'https://tfl.gov.uk/info-for/open-data-users/'),
          item('Postcodes', [
            'Postcode lookups by postcodes.io',
            'Contains Ordnance Survey data © Crown copyright and database right 2024',
            'Contains Royal Mail data © Royal Mail copyright and database right 2024',
            'Contains National Statistics data © Crown copyright and database right 2024',
            'Contains NRS data © Crown copyright and database right 2024',
          ], url: 'https://postcodes.io'),
          item('Maps', ['© OpenStreetMap contributors'], url: 'https://www.openstreetmap.org/copyright'),
          item('Letterboxd', ['Not affiliated with or endorsed by Letterboxd.']),
          ListTile(
            title: const Text('Open-source licences'),
            onTap: () => showLicensePage(context: context, applicationName: 'WhatsPlaying'),
          ),
        ],
      ),
    );
  }
}
