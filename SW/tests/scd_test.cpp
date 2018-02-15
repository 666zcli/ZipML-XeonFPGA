// Copyright (C) 2018 Kaan Kara - Systems Group, ETH Zurich

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.

// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.
//*************************************************************************

#include <stdio.h>
#include <stdint.h>
#include <pthread.h>

#include "../src/scd.h"

using namespace std;

#define VALUE_TO_INT_SCALER 0x00800000
#define NUM_VALUES_PER_LINE 16

int main(int argc, char* argv[]) {

	char* pathToDataset;
	uint32_t numSamples;
	uint32_t numFeatures;
	if (argc != 4) {
		cout << "Usage: ./ZipML.exe <pathToDataset> <numSamples> <numFeatures>" << endl;
		return 0;
	}
	else {
		pathToDataset = argv[1];
		numSamples = atoi(argv[2]);
		numFeatures = atoi(argv[3]);
	}

	uint32_t stepSizeShifter = 24;
	uint32_t numEpochs = 10;

	// Do SCD
	scd scd_app(VALUE_TO_INT_SCALER);

	scd_app.load_libsvm_data(pathToDataset, numSamples, numFeatures);

	scd_app.a_normalize(0, 'c');
	scd_app.b_normalize(0, 0, 0.0);

	scd_app.print_samples(1);

	for (uint32_t i = 1; i < 10; i++) {
		cout << scd_app.a[1][i] << endl;
		cout << (int)(scd_app.a[1][i]*VALUE_TO_INT_SCALER) << endl;
		cout << "delta: " << (int)(scd_app.a[1][i]*VALUE_TO_INT_SCALER) - (int)(scd_app.a[1][i-1]*VALUE_TO_INT_SCALER) << endl;
	}

	// scd_app.float_linreg_SCD(NULL, numEpochs, numSamples, 1.0/(1 << stepSizeShifter));
	// scd_app.float_linreg_SCD(NULL, numEpochs, 256, 1.0/(1 << stepSizeShifter));
}