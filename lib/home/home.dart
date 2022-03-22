import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../domain/Dog.dart';
import '../domain/User.dart';
import '../domain/Walk.dart';

final dogRef = FirebaseFirestore.instance.collection('dogs').withConverter(
    fromFirestore: (snapshots, _) => Dog.fromJson(snapshots.data()!),
    toFirestore: (dog, _) => dog.toJson());

final walkRef = FirebaseFirestore.instance.collection('walks').withConverter(
    fromFirestore: (snapshots, _) => Walk.fromJson(snapshots.data()!),
    toFirestore: (walk, _) => walk.toJson());

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Widget get appTitle {
    return Row(
      children: const [
        Icon(Icons.pets),
        Text('Pow Pow Steps'),
        Icon(Icons.pets),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final _user = Provider.of<UserState>(context).getUser();
    return Scaffold(
      appBar: AppBar(title: appTitle),
      body: StreamBuilder<QuerySnapshot<Dog>>(
        stream:
            dogRef.where('walkersIds', arrayContains: _user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(snapshot.error.toString()),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.requireData;
          return ListView.builder(
            itemCount: data.size,
            itemBuilder: (context, index) {
              return _DogListItem(data.docs[index].data(),
                  data.docs[index].reference, _user.uid);
            },
          );
        },
      ),
    );
  }
}

class _DogListItem extends StatelessWidget {
  final Dog dog;
  final DocumentReference<Dog> dogReference;
  final String userId;

  const _DogListItem(this.dog, this.dogReference, this.userId);

  Widget get image {
    return SizedBox(
      width: 200,
      height: 150,
      child: Image.network(dog.imageUrl),
    );
  }

  Widget get name {
    return Text(
      dog.name,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    );
  }

  Widget get details {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          name,
          WalkButton(dog: dog, dogReference: dogReference, userId: userId),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 200,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(children: [
            Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [image, Flexible(child: details)]),
            Flexible(child: WalkHistory(dog: dog))
          ]),
        ),
      ),
      color: Colors.amberAccent,
    );
  }
}

class WalkButton extends StatefulWidget {
  final Dog dog;
  final DocumentReference<Dog> dogReference;
  final String userId;

  const WalkButton(
      {Key? key,
      required this.dog,
      required this.dogReference,
      required this.userId})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _WalkButtonState();
}

class _WalkButtonState extends State<WalkButton> {
  Future<void> _onEndWalkPressed() async {
    final _walkDoc = await walkRef.doc(widget.dog.walkingId);
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_walkDoc, {'endAt': DateTime.now()});
    batch.update(widget.dogReference, {'walkingId': ''});
    batch.commit();
  }

  Future<void> _onWalkPressed() async {
    final _walkDoc = await walkRef.doc();
    final batch = FirebaseFirestore.instance.batch();
    batch.set(
        _walkDoc,
        Walk(
            uid: _walkDoc.id,
            dogId: widget.dog.uid,
            userId: widget.userId,
            startAt: DateTime.now(),
            endAt: DateTime.fromMillisecondsSinceEpoch(0)));
    batch.update(widget.dogReference, {
      'walkingId': _walkDoc.id,
      'walks': FieldValue.arrayUnion([_walkDoc])
    });
    batch.commit();
  }

  Future<DocumentSnapshot<Walk>> _getWalk() async {
    return widget.dog.walkingId.isEmpty
        ? await walkRef.doc().get()
        : await walkRef.doc(widget.dog.walkingId).get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _getWalk(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CircularProgressIndicator();
          }
          if (snapshot.hasError) {
            return const Text(
              'Error',
              style: TextStyle(color: Colors.red),
            );
          }

          if (!snapshot.hasData) {
            return const Text(
              'No Data',
              style: TextStyle(color: Colors.red),
            );
          }

          if (widget.dog.walkingId.isEmpty) {
            return ElevatedButton(
                onPressed: _onWalkPressed,
                child: const Text('Start Walk',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(primary: Colors.blueAccent));
          }
          return ElevatedButton(
              onPressed: _onEndWalkPressed,
              child:
                  const Text('End Walk', style: TextStyle(color: Colors.black)),
              style: ElevatedButton.styleFrom(primary: Colors.redAccent));
          ;
        });
  }
}

class WalkHistory extends StatefulWidget {
  final Dog dog;

  const WalkHistory({Key? key, required this.dog}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _WalkHistoryState();
}

class _WalkHistoryState extends State<WalkHistory> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Walk>>(
        stream: walkRef
            .where('dogId', isEqualTo: widget.dog.uid)
            .orderBy('endAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print(snapshot.error);
            return Center(
              child: Text(snapshot.error.toString()),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.requireData;
          return ListView.builder(
              itemCount: data.size,
              itemBuilder: (context, index) {
                final walk = data.docs[index].data();
                final duration = walk.endAt.difference(walk.startAt).inMinutes;

                String _walkInfo = '';
                if (walk.endAt.difference(DateTime.now()).inDays == 0) {
                  if (walk.endAt.day == DateTime.now().day) {
                    _walkInfo =
                        'Today ${DateFormat('HH:mm').format(walk.endAt)}';
                  } else {
                    _walkInfo =
                        'Yesterday ${DateFormat('HH:mm').format(walk.endAt)}';
                  }
                } else {
                  _walkInfo = DateFormat('yyyy-MM-dd HH:mm').format(walk.endAt);
                }

                return Card(
                    child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Row(children: [
                    Text(
                      _walkInfo,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    Text(' for $duration minutes')
                  ]),
                ));
              });
        });
  }
}
