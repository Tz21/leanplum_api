require 'spec_helper'

describe LeanplumApi::API do
  let(:api) { described_class.new }
  let(:first_user_id) { 123456 }
  let(:first_event_time) { Time.now.utc - 1.day }
  let(:last_event_time) { Time.now.utc }
  let(:users) do
    [{
      user_id: first_user_id,
      first_name: 'Mike',
      last_name: 'Jones',
      gender: 'm',
      email: 'still_tippin@test.com',
      create_date: '2010-01-01'.to_date,
      is_tipping: true,
      events: {
        eventName1: {
          count: 1,
          firstTime: first_event_time,
          lastTime: last_event_time
        }
      }
    }]
   end

  let(:devices) do
    [{
       device_id: 'fu123',
       appVersion: 'x42x',
       deviceModel: 'p0d',
       create_date: '2018-01-01'.to_date
     }]
  end

  context 'devices' do
    let(:expected_device_hash) do
      HashWithIndifferentAccess.new(
        appVersion: devices.first[:appVersion],
        deviceModel: devices.first[:deviceModel],
        create_date: devices.first[:create_date].iso8601
      )
    end
    let(:expected_response_hash) do
      {
        deviceId: devices.first[:device_id],
        action: 'setDeviceAttributes',
        deviceAttributes: expected_device_hash
      }
    end

    it 'build_device_attributes_hash' do
      expect(api.send(:build_device_attributes_hash, devices.first)).to eq(expected_response_hash)
    end

    context 'set_device_attributes' do
      context 'valid request' do
        it 'sets device attributes without error' do
          VCR.use_cassette('set_device_attributes') do
            expect { api.set_device_attributes(devices) }.to_not raise_error
          end
        end

        it 'sets device attributes without error' do
          VCR.use_cassette('set_device_attributes') do
            response = api.set_device_attributes(devices)
            expect(response.first['success']).to be true
          end
        end
      end
    end
  end

  context 'users' do
    let(:expected_ua_hash) do
      expected_ua_hash = HashWithIndifferentAccess.new(
        first_name: 'Mike',
        last_name: 'Jones',
        gender: 'm',
        email: 'still_tippin@test.com',
        create_date: '2010-01-01',
        is_tipping: true
      )
    end

    let(:expected_event_hash) do
      {
        'eventName1' => {
          'count' => 1,
          'firstTime' => first_event_time.strftime('%s').to_i,
          'lastTime' => last_event_time.strftime('%s').to_i
        }
      }
    end

    it 'builds user_attributes_hash' do
      expected_response_hash = {
        userId: first_user_id,
        action: 'setUserAttributes',
        userAttributes: expected_ua_hash,
        events: expected_event_hash
      }

      expect(api.send(:build_user_attributes_hash, users.first)).to eq(expected_response_hash)
    end

    it 'builds user_attributes_hash with devices' do
      user = users.first
      user[:devices] = devices

      expected_device_hash = HashWithIndifferentAccess.new(
        device_id: devices.first[:device_id],
        appVersion: devices.first[:appVersion],
        deviceModel: devices.first[:deviceModel],
        create_date: devices.first[:create_date]
      )

      expected_response_hash = {
        userId: first_user_id,
        action: 'setUserAttributes',
        devices: [expected_device_hash],
        events: expected_event_hash,
        userAttributes: expected_ua_hash
      }

      expect(api.send(:build_user_attributes_hash, users.first)).to eq(expected_response_hash)
    end

    context 'set_user_attributes' do
      context 'valid request' do
        it 'should successfully set user attributes' do
          VCR.use_cassette('set_user_attributes') do
            expect { api.set_user_attributes(users) }.to_not raise_error
          end
        end
      end

      context 'invalid request' do
        let(:broken_users) { users + [{ first_name: 'Moe' }] }

        it 'should raise an error' do
          expect{ api.set_user_attributes(broken_users) }.to raise_error(/No device_id or user_id in hash/)
        end
      end
    end

    context 'user_attributes' do
      it 'should get user attributes for this user' do
        VCR.use_cassette('export_user') do
          api.user_attributes(first_user_id).each do |k, v|
            if users.first[k.to_sym].is_a?(Date) || users.first[k.to_sym].is_a?(DateTime)
              expect(v).to eq(users.first[k.to_sym].strftime('%Y-%m-%d'))
            else
              expect(v).to eq(users.first[k.to_sym])
            end
          end
        end
      end
    end

    context 'export_users' do
      it 'should export users'
    end

    context 'reset_anomalous_users' do
      it 'should successfully call setUserAttributes with resetAnomalies' do
        VCR.use_cassette('reset_anomalous_user') do
          expect { api.reset_anomalous_users(first_user_id) }.to_not raise_error
        end
      end
    end
  end

  context 'events' do
    let(:timestamp) { '2015-05-01 01:02:03' }
    let(:purchase) { 'purchase' }
    let(:events) do
      [
        {
          user_id: first_user_id,
          event: purchase,
          time: Time.now.utc,
          some_timestamp: timestamp
        },
        {
          user_id: 54321,
          event: 'purchase_page_view',
          time: Time.now.utc - 10.minutes
        }
      ]
    end

    context '#build_event_attributes_hash' do
      let(:event_hash) do
        {
          userId: first_user_id,
          time: Time.now.utc.strftime('%s').to_i,
          action: 'track',
          event: purchase,
          params: { some_timestamp: timestamp }
        }
      end

      it 'builds the events format' do
        expect(api.send(:build_event_attributes_hash, events.first)).to eq(event_hash)
      end
    end

    context 'without user attributes' do
      context 'valid request' do
        it 'should successfully track session events' do
          VCR.use_cassette('track_events') do
            expect { api.track_events(events) }.to_not raise_error
          end
        end

        it 'should successfully track non session events' do
          VCR.use_cassette('track_offline_events') do
            expect { api.track_events(events, allow_offline: true) }.to_not raise_error
          end
        end
      end

      context 'invalid request' do
        let(:broken_events) { events + [{ event: 'no_user_id_event' }] }

        it 'should raise an error' do
          VCR.use_cassette('track_events_broken') do
            expect { api.track_events(broken_events) }.to raise_error(/No device_id or user_id in hash/)
          end
        end
      end

      context 'anomalous data force_anomalous_override' do
        let(:old_events) { events.map { |e| e[:time] -= 1.year; e } }

        it 'should successfully force the anomalous data override events' do
          VCR.use_cassette('track_events_anomaly_overrider') do
            expect { api.track_events(old_events, force_anomalous_override: true) }.to_not raise_error
          end
        end
      end
    end

    context 'along with user attributes' do
      it 'does not raise error' do
        VCR.use_cassette('track_events_and_attributes') do
          expect { api.track_multi(events: events, user_attributes: users) }.to_not raise_error
        end
      end

      it 'returns success response' do
        VCR.use_cassette('track_events_and_attributes') do
          response = api.track_multi(events: events, user_attributes: users)
          expect(response.first['success']).to be true
        end
      end
    end

    context 'user_events' do
      it 'should get user events for this user' do
        VCR.use_cassette('export_user') do
          expect(api.user_events(first_user_id)[purchase].keys.sort).to eq(['firstTime', 'count', 'lastTime'].sort)
        end
      end
    end
  end

  # Data export and content read only endpoints forbid use of devMode
  context 'non devMode methods' do
    around(:all) do |example|
      LeanplumApi.configure { |c| c.developer_mode = false }
      example.run
      LeanplumApi.configure { |c| c.developer_mode = true }
    end

    context 'data export methods' do
      context 'export_data' do
        context 'regular export' do
          it 'should request a data export job with a starttime' do
            VCR.use_cassette('export_data') do
              expect { api.export_data(Time.at(1438660800).utc) }.to raise_error LeanplumApi::BadResponseError
            end
          end

          it 'should request a data export job with start and end dates' do
            VCR.use_cassette('export_data_dates') do
              expect { api.export_data(Date.new(2017, 8, 5), Date.new(2017, 8, 6)) }.to_not raise_error
            end
          end
        end

        context 's3 export' do
          let(:s3_bucket_name) { 'bucket' }
          let(:s3_access_key) { 's3_access_key' }
          let(:s3_access_id) { 's3_access_id' }

          it 'should request an S3 export'
        end
      end

      context 'get_export_results' do
        it 'should get a status for a data export job' do
          VCR.use_cassette('get_export_results') do
            expect(api.get_export_results('export_4727756026281984_2904941266315269120')).to eq({
              files: ['https://leanplum_export.storage.googleapis.com/export-4727756026281984-d5969d55-f242-48a6-85a3-165af08e2306-output-0'],
              number_of_bytes: 36590,
              number_of_sessions: 101,
              state: LeanplumApi::API::EXPORT_FINISHED,
              s3_copy_status: nil
            })
          end
        end
      end
    end

    context 'content read only methods' do
      context 'ab tests' do
        it 'gets ab tests' do
          VCR.use_cassette('get_ab_tests') do
            expect(api.get_ab_tests).to eq([])
          end
        end

        it 'gets an ab test' do
          VCR.use_cassette('get_ab_test') do
            expect(api.get_ab_tests(1)).to eq([])
          end
        end
      end

      context 'messages' do
        it 'gets messages' do
          VCR.use_cassette('get_messages') do
            expect(api.get_messages).to eq([{
              'id' => 5670583287676928,
              'created' => 1440091595.799,
              'name' => 'New Message',
              'active' => false,
              'messageType' => 'Push Notification'
            }])
          end
        end

        it 'throws exception on missing message' do
          VCR.use_cassette('missing_message') do
            expect { api.get_message(1234) }.to raise_error LeanplumApi::ResourceNotFoundError
          end
        end
      end

      it 'gets vars' do
        pending 'Docs are extremely unclear about what getVars and setVars even do'

        VCR.use_cassette('get_vars') do
          expect(api.get_vars(users.first[:user_id])).to eq({ 'test_var' => 1 })
        end
      end
    end
  end
end
